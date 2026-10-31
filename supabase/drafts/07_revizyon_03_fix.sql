-- ============================================================================
-- 07_revizyon_03_fix.sql
-- Revizyon 03 Artımlı Sunucu Düzeltme Paketi
--
-- Düzeltmeler:
-- 1. Kusur 1.1: v_clan_shame_board ve v_global_shame_board security_invoker = true
--    için gereken public.users (clan_role, weekly_car_taxi_trips, weekly_car_taxi_km,
--    weekly_wasted_co2_kg) sütunlarına SELECT izni verildi.
-- 2. Kusur 1.2 & 1.3: rpc_record_transit içine FOR UPDATE kullanıcı satır kilidi
--    ve otomatik biniş ('AUTO_BUS_TRIP') ile QR/NFC ortak 45 dk cooldown kontrolü eklendi.
-- 3. Kusur 1.4: rpc_record_bus_trip içinde public.processed_events tablosuna
--    yazarken NOT NULL olan 'event_type' ('bus_trip') parametresi eklendi.
-- ============================================================================

-- 1. Utanç Panoları İçin Sütun İzinleri (Security Invoker Desteği)
GRANT SELECT (
    clan_role,
    weekly_car_taxi_trips,
    weekly_car_taxi_km,
    weekly_wasted_co2_kg
) ON public.users TO anon, authenticated;


-- 2. rpc_record_transit Fonksiyonu: FOR UPDATE Kilidi ve Ters Sırada QR/Otomatik Uzlaştırma
CREATE OR REPLACE FUNCTION public.rpc_record_transit(
    p_event_id TEXT,
    p_stop_code TEXT,
    p_verification_method TEXT DEFAULT 'QR'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_cached RECORD;
    v_stop RECORD;
    v_user RECORD;
    v_last_scan TIMESTAMPTZ;
    v_raw_code TEXT;
    v_canonical_stop TEXT;
    v_clan_id INT;
    v_rem_sec INT;
    v_res JSONB;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    IF p_event_id IS NULL OR TRIM(p_event_id) = '' THEN
        RAISE EXCEPTION 'event_id boş olamaz';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || ':' || p_event_id));

    -- İdempotency kontrolü
    SELECT * INTO v_cached
    FROM public.processed_events
    WHERE user_id = v_user_id AND event_id = p_event_id;

    IF FOUND THEN
        RETURN v_cached.result_json || jsonb_build_object('duplicate', true);
    END IF;

    -- Kullanıcı satırını kilitle (Eşzamanlı yarış durumlarını ve çift settlement'ı engeller)
    SELECT * INTO v_user FROM public.users WHERE id = v_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kullanıcı bulunamadı';
    END IF;

    -- Durak kodunu ve URI yükünü kanonikleştir (QR ve NFC aynı durağa eşlenir)
    v_raw_code := TRIM(COALESCE(p_stop_code, ''));
    v_canonical_stop := v_raw_code;
    IF v_canonical_stop LIKE 'YESILADIM://TRANSIT/%' THEN
        v_canonical_stop := split_part(substring(v_canonical_stop from 21), '?', 1);
    ELSIF v_canonical_stop LIKE '%?%' THEN
        v_canonical_stop := split_part(v_canonical_stop, '?', 1);
    END IF;
    v_canonical_stop := UPPER(TRIM(v_canonical_stop));

    SELECT * INTO v_stop
    FROM public.transit_stops
    WHERE UPPER(stop_code) = v_canonical_stop
       OR UPPER(nfc_uid) = UPPER(v_raw_code)
       OR qr_payload = v_raw_code
       OR qr_payload LIKE (v_raw_code || '%')
       OR UPPER(stop_code) = UPPER(v_raw_code)
    LIMIT 1;

    IF v_stop.id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Geçersiz veya bilinmeyen durak kodu');
    END IF;

    -- Cooldown kontrolü: Şartname gereği tam 45 DAKİKA
    -- Ortak kilit: Aynı durak veya otomatik biniş ('AUTO_BUS_TRIP') son 45 dk içinde ödüllenmişse engellenir
    SELECT last_scanned_at INTO v_last_scan
    FROM public.transit_cooldowns
    WHERE user_id = v_user_id
      AND (stop_code = v_stop.stop_code OR stop_code = 'AUTO_BUS_TRIP')
      AND last_scanned_at >= NOW() - INTERVAL '45 minutes'
    ORDER BY last_scanned_at DESC
    LIMIT 1;

    IF v_last_scan IS NOT NULL THEN
        v_rem_sec := CEIL(EXTRACT(EPOCH FROM (v_last_scan + INTERVAL '45 minutes' - NOW())));
        v_res := jsonb_build_object(
            'ok', false,
            'cooldown', true,
            'remaining_seconds', v_rem_sec,
            'message', 'Aynı otobüsü iki kere mi satın aldın? Sonraki biniş puanı için ' || CEIL(v_rem_sec / 60.0)::TEXT || ' dk bekle!'
        );
        RETURN v_res;
    END IF;

    -- Cooldown kaydını güncelle
    INSERT INTO public.transit_cooldowns (user_id, stop_code, last_scanned_at)
    VALUES (v_user_id, v_stop.stop_code, NOW())
    ON CONFLICT (user_id, stop_code)
    DO UPDATE SET last_scanned_at = NOW();

    -- Aktivite logu oluştur (Sunucu veritabanı puan ve tasarruf değerini kullanır)
    INSERT INTO public.activities (
        event_id, user_id, activity_type, distance_km,
        transit_stop_id, points_earned, co2_delta_kg,
        verification_status, feedback_message, created_at
    ) VALUES (
        p_event_id, v_user_id, 'public_transit', v_stop.avg_trip_km,
        v_stop.id, v_stop.points_reward, v_stop.co2_saved_per_trip_kg,
        'verified', v_stop.route_name || ' doğrulandı (' || p_verification_method || ').', NOW()
    );

    -- Kullanıcı puan ve co2 güncelle
    UPDATE public.users
    SET weekly_points = weekly_points + v_stop.points_reward,
        all_time_points = all_time_points + v_stop.points_reward,
        weekly_saved_co2_kg = weekly_saved_co2_kg + v_stop.co2_saved_per_trip_kg,
        last_active_at = NOW()
    WHERE id = v_user_id
    RETURNING clan_id INTO v_clan_id;

    -- Klan puan ve co2 güncelle
    IF v_clan_id IS NOT NULL THEN
        UPDATE public.clans
        SET weekly_points = weekly_points + v_stop.points_reward,
            all_time_points = all_time_points + v_stop.points_reward,
            weekly_saved_co2_kg = weekly_saved_co2_kg + v_stop.co2_saved_per_trip_kg
        WHERE id = v_clan_id;
    END IF;

    v_res := jsonb_build_object(
        'ok', true,
        'duplicate', false,
        'points_awarded', v_stop.points_reward,
        'co2_saved_kg', v_stop.co2_saved_per_trip_kg,
        'stop_name', v_stop.stop_name,
        'route_name', v_stop.route_name
    );

    INSERT INTO public.processed_events (user_id, event_id, event_type, result_json)
    VALUES (v_user_id, p_event_id, 'transit_scan', v_res);

    RETURN v_res;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_record_transit TO authenticated;


-- 3. rpc_record_bus_trip Fonksiyonu: NOT NULL event_type Eklendi
CREATE OR REPLACE FUNCTION public.rpc_record_bus_trip(
    p_event_id TEXT,
    p_distance_km NUMERIC,
    p_bus_score INT DEFAULT 60,
    p_is_short_penalty BOOLEAN DEFAULT false,
    p_confidence NUMERIC DEFAULT 1.0,
    p_stop_code TEXT DEFAULT NULL,
    p_explanation TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_cached RECORD;
    v_user RECORD;
    v_pts_delta INT := 0;
    v_actual_deducted INT := 0;
    v_co2_saved NUMERIC(8,2) := 0.00;
    v_msg TEXT;
    v_last_scan TIMESTAMPTZ;
    v_last_stop VARCHAR(30);
    v_canonical_stop VARCHAR(30) := COALESCE(NULLIF(TRIM(p_stop_code), ''), 'AUTO_BUS_TRIP');
    v_is_short BOOLEAN;
    v_already_qr_settled BOOLEAN := false;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    IF p_event_id IS NULL OR TRIM(p_event_id) = '' THEN
        RAISE EXCEPTION 'event_id boş olamaz';
    END IF;

    -- 1. Sayısal Aralık ve NaN Koruması (Postgres finite numeric doğrulaması)
    IF p_distance_km IS NULL 
       OR p_distance_km = 'NaN'::numeric 
       OR NOT (p_distance_km > 0.0 AND p_distance_km <= 200.0) THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Geçersiz mesafe ölçümü (0 - 200 km aralığında olmalıdır).');
    END IF;

    IF p_bus_score IS NULL OR p_bus_score < 0 OR p_bus_score > 100 THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Geçersiz otobüs olasılık skoru (0 - 100 arası).');
    END IF;

    IF p_confidence IS NULL 
       OR p_confidence = 'NaN'::numeric 
       OR NOT (p_confidence >= 0.0 AND p_confidence <= 1.0) THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Geçersiz sensör güven katsayısı.');
    END IF;

    -- Güven Eşiği Kontrolü: Güven < 0.60 veya skor < 60 ise otomatik ödül/ceza verilmez
    IF p_confidence < 0.60 OR p_bus_score < 60 THEN
        RETURN jsonb_build_object(
            'ok', false,
            'message', 'Yetersiz sensör güveni veya otobüs olasılık skoru (<60); otomatik işlem yapılmadı.'
        );
    END IF;

    -- 2. Advisory Lock (Yarış durumu engeli)
    PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || ':bus_trip:' || p_event_id));

    -- 3. Idempotency Kontrolü
    SELECT * INTO v_cached FROM public.processed_events WHERE user_id = v_user_id AND event_id = p_event_id;
    IF FOUND THEN
        RETURN v_cached.result_json || jsonb_build_object('duplicate', true);
    END IF;

    -- 4. KULLANICI SATIR KİLİDİ (FOR UPDATE) - Tüm transit kontrollerinden ÖNCE kilitlenir!
    SELECT * INTO v_user FROM public.users WHERE id = v_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kullanıcı bulunamadı';
    END IF;

    -- 5. Ortak Yolculuk (Joint Transit Settlement) Kontrolü:
    -- Son 45 dk içinde herhangi bir transit kaydı (QR, NFC veya önceki biniş) var mı?
    SELECT last_scanned_at, stop_code INTO v_last_scan, v_last_stop
    FROM public.transit_cooldowns
    WHERE user_id = v_user_id
      AND last_scanned_at >= NOW() - INTERVAL '45 minutes'
    ORDER BY last_scanned_at DESC
    LIMIT 1;

    IF v_last_scan IS NOT NULL THEN
        v_already_qr_settled := true;
    END IF;

    -- 6. Kısa Otobüs Kuralı: Server Mesafesi Kesin Karar Vericidir!
    -- p_is_short_penalty tek başına uzun mesafeyi kısa sayamaz. Mesafe <= 0.50 km olmalıdır.
    v_is_short := (p_distance_km <= 0.50);

    IF v_is_short THEN
        -- KISA OTOBÜS YOLCULUĞU (≤ 500m):
        -- Şartname gereği net sonuç -3 puan olmalıdır.
        IF v_already_qr_settled THEN
            -- Yolcu biniş anında QR okutup +3 puan almıştı. Şimdi yolculuk <=500m bitti.
            -- Net sonucun -3 olması için: +3 geri alınır (-3) ve ilave ceza (-3) verilir = -6 puan!
            v_actual_deducted := LEAST(v_user.weekly_points, 6);
            v_pts_delta := -v_actual_deducted;
            v_co2_saved := 0.00;
            v_msg := COALESCE(p_explanation, 'Kısa otobüs yolculuğu (≤500m): Başlangıçtaki QR ödülü (+3) iptal edildi ve -3 ceza kesildi (Net -' || v_actual_deducted || ' puan).');
        ELSE
            -- QR okutulmamıştı, saf otomatik tespit: 3 puan düşülür.
            v_actual_deducted := LEAST(v_user.weekly_points, 3);
            v_pts_delta := -v_actual_deducted;
            v_co2_saved := 0.00;
            IF v_actual_deducted > 0 THEN
                v_msg := COALESCE(p_explanation, 'Kısa otobüs yolculuğu (≤500m): Dingil gibi yürümek yerine otobüse bindin! -' || v_actual_deducted || ' puan ceza kesildi.');
            ELSE
                v_msg := COALESCE(p_explanation, 'Kısa otobüs yolculuğu (≤500m): Puanınız zaten 0 olduğu için ilave puan düşülemedi.');
            END IF;
        END IF;

        UPDATE public.users
        SET weekly_points = weekly_points - v_actual_deducted,
            last_active_at = NOW()
        WHERE id = v_user_id;

        IF v_user.clan_id IS NOT NULL AND v_actual_deducted > 0 THEN
            UPDATE public.clans
            SET weekly_points = GREATEST(0, weekly_points - v_actual_deducted)
            WHERE id = v_user.clan_id;
        END IF;

    ELSE
        -- STANDART OTOBÜS YOLCULUĞU (> 500m):
        v_co2_saved := ROUND(p_distance_km * (0.192 - 0.035), 2);

        IF v_already_qr_settled THEN
            -- Kullanıcı binişte QR ile zaten +3 puan aldı; mükerrer puan verilmez (Tek yolculuk tek ödül)
            v_pts_delta := 0;
            v_msg := COALESCE(p_explanation, 'Otobüs yolculuğu tamamlandı (' || p_distance_km || ' km). Binişte QR ile puan alındığı için ilave puan verilmedi, ' || v_co2_saved || ' kg CO₂ tasarrufu işlendi.');

            UPDATE public.users
            SET weekly_saved_co2_kg = weekly_saved_co2_kg + v_co2_saved,
                last_active_at = NOW()
            WHERE id = v_user_id;

            IF v_user.clan_id IS NOT NULL THEN
                UPDATE public.clans
                SET weekly_saved_co2_kg = weekly_saved_co2_kg + v_co2_saved
                WHERE id = v_user.clan_id;
            END IF;
        ELSE
            -- Binişte QR okutulmamış, otomatik doğrulama ile +3 puan verilir
            v_pts_delta := 3;
            v_msg := COALESCE(p_explanation, 'Otobüs / Dolmuş yolculuğu otomatik doğrulandı! (+3 Puan, ' || v_co2_saved || ' kg CO₂ tasarrufu)');

            UPDATE public.users
            SET weekly_points = weekly_points + v_pts_delta,
                all_time_points = all_time_points + v_pts_delta,
                weekly_saved_co2_kg = weekly_saved_co2_kg + v_co2_saved,
                last_active_at = NOW()
            WHERE id = v_user_id;

            IF v_user.clan_id IS NOT NULL THEN
                UPDATE public.clans
                SET weekly_points = weekly_points + v_pts_delta,
                    all_time_points = all_time_points + v_pts_delta,
                    weekly_saved_co2_kg = weekly_saved_co2_kg + v_co2_saved
                WHERE id = v_user.clan_id;
            END IF;
        END IF;
    END IF;

    -- 7. Cooldown Tablosunu Güncelle (Sonraki 45 dk için mükerrer işlemleri önler)
    INSERT INTO public.transit_cooldowns (user_id, stop_code, last_scanned_at)
    VALUES (v_user_id, v_canonical_stop, NOW())
    ON CONFLICT (user_id, stop_code)
    DO UPDATE SET last_scanned_at = NOW();

    -- 8. Aktiviteyi Kaydet (01_schema.sql CHECK kısıtları ile %100 uyumlu)
    INSERT INTO public.activities (
        event_id, user_id, activity_type, distance_km,
        points_earned, co2_delta_kg, verification_status, feedback_message
    ) VALUES (
        p_event_id, v_user_id, 'public_transit', p_distance_km,
        v_pts_delta, v_co2_saved, 'verified', v_msg
    );

    -- 9. İdempotent Olay Kaydı (event_type NOT NULL kısıtı ile tam uyumlu)
    INSERT INTO public.processed_events (user_id, event_id, event_type, result_json)
    VALUES (v_user_id, p_event_id, 'bus_trip', jsonb_build_object(
        'ok', true,
        'points_delta', v_pts_delta,
        'co2_saved_kg', v_co2_saved,
        'is_short_penalty', v_is_short,
        'already_qr_settled', v_already_qr_settled,
        'message', v_msg
    ));

    RETURN jsonb_build_object(
        'ok', true,
        'points_delta', v_pts_delta,
        'co2_saved_kg', v_co2_saved,
        'is_short_penalty', v_is_short,
        'already_qr_settled', v_already_qr_settled,
        'message', v_msg
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_record_bus_trip FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_record_bus_trip TO authenticated;
