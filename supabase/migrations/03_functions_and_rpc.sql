-- ============================================================================
-- 03_functions_and_rpc.sql
-- Atomik İşlemler, İdempotent Olaylar, 45dk Cooldown, Eşik Doğrulama ve Admin RPC
-- Proje: Green_Project (fhaxxraibydsjikxacbb)
-- ============================================================================

-- 1. Lig Kademesini Puan Eşiklerine Göre Hesaplama Fonksiyonu (STABLE)
CREATE OR REPLACE FUNCTION public.compute_league_tier(p_points INT, p_type VARCHAR)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        (SELECT tier FROM public.leagues
         WHERE league_type = p_type AND min_points <= p_points
         ORDER BY min_points DESC LIMIT 1),
        1
    );
$$;

-- 2. Kullanıcı Lig Kademesi Otomatik Tetikleyicisi
CREATE OR REPLACE FUNCTION public.trg_sync_user_league_tier()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.league_tier := public.compute_league_tier(NEW.weekly_points, 'individual');
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_league_tier ON public.users;
CREATE TRIGGER trg_users_league_tier
    BEFORE INSERT OR UPDATE OF weekly_points ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_sync_user_league_tier();

-- 3. Klan Lig Kademesi Otomatik Tetikleyicisi
CREATE OR REPLACE FUNCTION public.trg_sync_clan_league_tier()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.league_tier := public.compute_league_tier(NEW.weekly_points, 'clan');
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_clans_league_tier ON public.clans;
CREATE TRIGGER trg_clans_league_tier
    BEFORE INSERT OR UPDATE OF weekly_points ON public.clans
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_sync_clan_league_tier();

-- ============================================================================
-- RPC İŞLEM FONKSİYONLARI (SECURITY DEFINER + search_path sabitlemesi)
-- ============================================================================

-- 4. İlk Profil Senkronizasyonu & İstemci Bağlantısı (Legacy Yerel Veri Dahil)
CREATE OR REPLACE FUNCTION public.rpc_sync_initial_profile(
    p_device_id TEXT,
    p_nickname TEXT,
    p_clan_id INT DEFAULT NULL,
    p_avatar_url TEXT DEFAULT 'assets/avatars/user_sen.png',
    p_bio TEXT DEFAULT '',
    p_legacy_steps INT DEFAULT 0,
    p_legacy_points INT DEFAULT 0,
    p_legacy_gold INT DEFAULT 100,
    p_legacy_co2 NUMERIC DEFAULT 0.00,
    p_clan_name TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user RECORD;
    v_safe_points INT;
    v_safe_gold INT;
    v_safe_co2 NUMERIC;
    v_safe_steps INT;
    v_resolved_clan_id INT := NULL;
    v_streak INT := 0;
    v_streak_date DATE := NULL;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim: auth.uid() doğrulanamadı';
    END IF;

    -- Kullanıcı zaten kayıtlı mı kontrol et
    SELECT * INTO v_user FROM public.users WHERE id = v_user_id;

    IF FOUND THEN
        -- Kayıt zaten var: Mevcut sunucu durumunu dön (Sunucu gerçeğin tek kaynağıdır)
        RETURN jsonb_build_object(
            'ok', true,
            'is_new', false,
            'user', row_to_json(v_user)
        );
    END IF;

    -- Legacy yerel veriyi güvenli sınırlara tabi tut (Hile/Taşma Koruması)
    v_safe_points := LEAST(GREATEST(COALESCE(p_legacy_points, 0), 0), 25000);
    v_safe_gold   := LEAST(GREATEST(COALESCE(p_legacy_gold, 100), 100), 10000);
    v_safe_co2    := LEAST(GREATEST(COALESCE(p_legacy_co2, 0.00), 0.00), 200.00);
    v_safe_steps  := LEAST(GREATEST(COALESCE(p_legacy_steps, 0), 0), 50000);

    -- Klan ID çözümleme: Telefonda SQL'de olmayan klan varsa isme göre ara, yoksa NULL düş
    IF p_clan_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM public.clans WHERE id = p_clan_id) THEN
            v_resolved_clan_id := p_clan_id;
        ELSIF p_clan_name IS NOT NULL THEN
            SELECT id INTO v_resolved_clan_id FROM public.clans WHERE name = p_clan_name OR tag = p_clan_name LIMIT 1;
        END IF;
    ELSIF p_clan_name IS NOT NULL THEN
        SELECT id INTO v_resolved_clan_id FROM public.clans WHERE name = p_clan_name OR tag = p_clan_name LIMIT 1;
    END IF;

    -- 6.000 adım streak başlangıcı
    IF v_safe_steps >= 6000 THEN
        v_streak := 1;
        v_streak_date := CURRENT_DATE;
    END IF;

    -- Yeni kullanıcı kaydı oluştur
    INSERT INTO public.users (
        id, device_id, nickname, avatar_url, clan_id, bio,
        today_steps, weekly_points, all_time_points, gold_coins,
        streak_days, last_streak_date,
        weekly_saved_co2_kg, is_demo, last_active_at, created_at
    ) VALUES (
        v_user_id,
        COALESCE(NULLIF(TRIM(p_device_id), ''), 'DEV-' || v_user_id::text),
        COALESCE(NULLIF(TRIM(p_nickname), ''), 'Yeşil Gezgin'),
        COALESCE(NULLIF(TRIM(p_avatar_url), ''), 'assets/avatars/user_sen.png'),
        v_resolved_clan_id,
        SUBSTRING(COALESCE(p_bio, '') FROM 1 FOR 160),
        v_safe_steps,
        v_safe_points,
        v_safe_points,
        v_safe_gold,
        v_streak,
        v_streak_date,
        v_safe_co2,
        false,
        NOW(),
        NOW()
    )
    RETURNING * INTO v_user;

    -- Klan seçilmişse üye sayısını artır ve yeni gerçek kullanıcının puanını ekle
    IF v_resolved_clan_id IS NOT NULL THEN
        UPDATE public.clans
        SET member_count = member_count + 1,
            weekly_points = weekly_points + v_safe_points,
            all_time_points = all_time_points + v_safe_points,
            weekly_saved_co2_kg = weekly_saved_co2_kg + v_safe_co2
        WHERE id = v_resolved_clan_id;
    END IF;

    -- Başlangıç envanteri olarak standart avatar ver
    INSERT INTO public.user_inventory (user_id, item_slug)
    VALUES (v_user_id, 'ava_cycling_pro')
    ON CONFLICT DO NOTHING;

    RETURN jsonb_build_object(
        'ok', true,
        'is_new', true,
        'user', row_to_json(v_user)
    );
END;
$$;

-- 5. Kullanıcının Kendi Profilini, Envanterini ve Klanını Getiren Güvenli RPC
CREATE OR REPLACE FUNCTION public.rpc_get_my_profile()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user RECORD;
    v_clan RECORD;
    v_inventory JSONB;
    v_is_admin BOOLEAN := false;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim: auth.uid() doğrulanamadı';
    END IF;

    SELECT * INTO v_user FROM public.users WHERE id = v_user_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Kullanıcı profili bulunamadı');
    END IF;

    SELECT * INTO v_clan FROM public.clans WHERE id = v_user.clan_id;

    SELECT COALESCE(jsonb_agg(item_slug), '[]'::jsonb)
    INTO v_inventory
    FROM public.user_inventory
    WHERE user_id = v_user_id;

    SELECT EXISTS (SELECT 1 FROM public.server_admins WHERE user_id = v_user_id) INTO v_is_admin;

    RETURN jsonb_build_object(
        'ok', true,
        'user', row_to_json(v_user),
        'clan', CASE WHEN v_clan.id IS NOT NULL THEN row_to_json(v_clan) ELSE NULL END,
        'inventory', v_inventory,
        'is_admin', v_is_admin
    );
END;
$$;

-- 6. Profil Bilgilerini Güncelleme RPC (Sahiplik & 160 Karakter Bio Sınırı)
CREATE OR REPLACE FUNCTION public.rpc_update_profile(
    p_nickname TEXT,
    p_bio TEXT DEFAULT NULL,
    p_photo_path TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_clean_nick TEXT;
    v_clean_bio TEXT;
    v_user RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    SELECT * INTO v_user FROM public.users WHERE id = v_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kullanıcı bulunamadı';
    END IF;
    IF v_user.is_demo THEN
        RAISE EXCEPTION 'Demo profiller değiştirilemez';
    END IF;

    v_clean_nick := TRIM(COALESCE(p_nickname, v_user.nickname));
    IF LENGTH(v_clean_nick) < 2 OR LENGTH(v_clean_nick) > 50 THEN
        RAISE EXCEPTION 'Geçersiz isim uzunluğu (2-50 karakter)';
    END IF;

    IF p_bio IS NOT NULL THEN
        v_clean_bio := SUBSTRING(TRIM(p_bio) FROM 1 FOR 160);
    ELSE
        v_clean_bio := v_user.bio;
    END IF;

    UPDATE public.users
    SET nickname = v_clean_nick,
        bio = v_clean_bio,
        photo_path = COALESCE(p_photo_path, photo_path),
        last_active_at = NOW()
    WHERE id = v_user_id
    RETURNING * INTO v_user;

    RETURN jsonb_build_object('ok', true, 'user', row_to_json(v_user));
END;
$$;

-- 7. Klana Katılma / Klan Değiştirme RPC
CREATE OR REPLACE FUNCTION public.rpc_join_clan(p_clan_id INT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_old_clan_id INT;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clans WHERE id = p_clan_id) THEN
        RAISE EXCEPTION 'Geçersiz klan seçimi';
    END IF;

    SELECT clan_id INTO v_old_clan_id FROM public.users WHERE id = v_user_id;

    IF v_old_clan_id = p_clan_id THEN
        RETURN jsonb_build_object('ok', true, 'message', 'Zaten bu klandasınız', 'clan_id', p_clan_id);
    END IF;

    -- Eski klandan üye düş
    IF v_old_clan_id IS NOT NULL THEN
        UPDATE public.clans
        SET member_count = GREATEST(member_count - 1, 0)
        WHERE id = v_old_clan_id;
    END IF;

    -- Yeni klana üye ekle
    UPDATE public.clans
    SET member_count = member_count + 1
    WHERE id = p_clan_id;

    -- Kullanıcı klanını güncelle
    UPDATE public.users
    SET clan_id = p_clan_id,
        last_active_at = NOW()
    WHERE id = v_user_id;

    RETURN jsonb_build_object('ok', true, 'new_clan_id', p_clan_id);
END;
$$;

-- 8. İdempotent Adım Ekleme & Sunucu Doğrulamalı Puanlama RPC
CREATE OR REPLACE FUNCTION public.rpc_record_steps(
    p_event_id TEXT,
    p_step_count INT,
    p_distance_km NUMERIC,
    p_points_earned INT DEFAULT NULL,
    p_co2_saved_kg NUMERIC DEFAULT NULL
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
    v_base_steps INT;
    v_new_today_steps INT;
    v_points_awarded INT;
    v_co2_saved NUMERIC(8,2);
    v_streak INT;
    v_last_streak_date DATE;
    v_res JSONB;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    IF p_event_id IS NULL OR TRIM(p_event_id) = '' THEN
        RAISE EXCEPTION 'event_id boş olamaz';
    END IF;

    -- Eşzamanlı çağrılarda yarış durumunu engellemek için kullanıcı+event bazlı işlem kilidi
    PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || ':' || p_event_id));

    -- İdempotency Kontrolü: Olay daha önce işlendi mi?
    SELECT * INTO v_cached
    FROM public.processed_events
    WHERE user_id = v_user_id AND event_id = p_event_id;

    IF FOUND THEN
        RETURN v_cached.result_json || jsonb_build_object('duplicate', true);
    END IF;

    -- Değer doğrulama sınırları (Aşırı veya geçersiz girdi ret)
    IF p_step_count IS NULL OR p_step_count <= 0 OR p_step_count > 50000 THEN
        RAISE EXCEPTION 'Geçersiz adım sayısı: %', p_step_count;
    END IF;
    IF p_distance_km IS NULL OR p_distance_km < 0 OR p_distance_km > 100 OR p_distance_km != p_distance_km THEN
        RAISE EXCEPTION 'Geçersiz mesafe miktarı';
    END IF;

    -- Kullanıcı satırını atomik kilitle
    SELECT * INTO v_user FROM public.users WHERE id = v_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kullanıcı bulunamadı';
    END IF;

    -- Gün değişmişse bugünkü adımları sıfırdan başlat
    IF v_user.last_active_at::date < CURRENT_DATE THEN
        v_base_steps := 0;
        IF v_user.last_streak_date < CURRENT_DATE - INTERVAL '1 day' THEN
            v_streak := 0;
        ELSE
            v_streak := v_user.streak_days;
        END IF;
    ELSE
        v_base_steps := v_user.today_steps;
        v_streak := v_user.streak_days;
    END IF;

    v_new_today_steps := v_base_steps + p_step_count;

    -- Sunucu Tarafı Puanlama: Her tamamlanan 1.000 adım = 5 puan (İstemci parametresine güvenilmez)
    v_points_awarded := ((v_new_today_steps / 1000) - (v_base_steps / 1000)) * 5;
    IF v_points_awarded < 0 THEN
        v_points_awarded := 0;
    END IF;

    -- Sunucu Tarafı CO₂ Tasarrufu Hesaplama: Mesafe × 0.19 kg/km
    v_co2_saved := ROUND(GREATEST(p_distance_km, 0) * 0.19, 2);

    -- 6.000 Adım Streak Kuralı (REVIZYON_02 ile tutarlı)
    IF v_new_today_steps >= 6000 AND (v_user.last_streak_date IS NULL OR v_user.last_streak_date < CURRENT_DATE) THEN
        IF v_user.last_streak_date = CURRENT_DATE - INTERVAL '1 day' THEN
            v_streak := v_streak + 1;
        ELSE
            v_streak := 1;
        END IF;
        v_last_streak_date := CURRENT_DATE;
    ELSE
        v_last_streak_date := v_user.last_streak_date;
    END IF;

    -- 1. Aktivite loguna yaz
    INSERT INTO public.activities (
        event_id, user_id, activity_type, steps_count,
        distance_km, points_earned, co2_delta_kg,
        verification_status, feedback_message, created_at
    ) VALUES (
        p_event_id, v_user_id, 'walk', p_step_count,
        p_distance_km, v_points_awarded, v_co2_saved,
        'verified', 'Yürüyüş adımları başarıyla kaydedildi.', NOW()
    );

    -- 2. Kullanıcı bakiyesini ve sayaçlarını güncelle
    UPDATE public.users
    SET today_steps = v_new_today_steps,
        weekly_points = weekly_points + v_points_awarded,
        all_time_points = all_time_points + v_points_awarded,
        weekly_saved_co2_kg = weekly_saved_co2_kg + v_co2_saved,
        streak_days = v_streak,
        last_streak_date = v_last_streak_date,
        last_active_at = NOW()
    WHERE id = v_user_id;

    -- 3. Klan toplamını atomik olarak güncelle
    IF v_user.clan_id IS NOT NULL THEN
        UPDATE public.clans
        SET weekly_points = weekly_points + v_points_awarded,
            all_time_points = all_time_points + v_points_awarded,
            weekly_saved_co2_kg = weekly_saved_co2_kg + v_co2_saved
        WHERE id = v_user.clan_id;
    END IF;

    v_res := jsonb_build_object(
        'ok', true,
        'duplicate', false,
        'points_awarded', v_points_awarded,
        'co2_saved_kg', v_co2_saved,
        'steps_added', p_step_count,
        'streak_days', v_streak
    );

    -- 4. Olayı idempotency tablosuna kaydet
    INSERT INTO public.processed_events (user_id, event_id, event_type, result_json)
    VALUES (v_user_id, p_event_id, 'step_sync', v_res);

    RETURN v_res;
END;
$$;

-- 9. İdempotent ve 45 Dakika Cooldown Korumalı Toplu Taşıma Okutma RPC (Ortak QR/NFC)
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

    -- Cooldown kontrolü: Şartname gereği tam 45 DAKİKA (QR ve NFC ortak kanonik durak)
    SELECT last_scanned_at INTO v_last_scan
    FROM public.transit_cooldowns
    WHERE user_id = v_user_id AND stop_code = v_stop.stop_code;

    IF v_last_scan IS NOT NULL AND (NOW() - v_last_scan) < INTERVAL '45 minutes' THEN
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

-- 10. Bisiklet Sürüşü & Hız/İvme Doğrulama RPC (bike50ve35 / 25variance0.12 / 0.19 Tasarruf)
CREATE OR REPLACE FUNCTION public.rpc_record_bike(
    p_event_id TEXT,
    p_distance_km NUMERIC,
    p_avg_speed_kmh NUMERIC,
    p_max_speed_kmh NUMERIC,
    p_accel_variance NUMERIC DEFAULT NULL,
    p_points_earned INT DEFAULT NULL,
    p_co2_saved_kg NUMERIC DEFAULT NULL,
    p_is_spoof BOOLEAN DEFAULT FALSE,
    p_reject_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_cached RECORD;
    v_clan_id INT;
    v_points INT;
    v_co2_saved NUMERIC(8,2);
    v_wasted_co2 NUMERIC(8,2);
    v_res JSONB;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    IF p_event_id IS NULL OR TRIM(p_event_id) = '' THEN
        RAISE EXCEPTION 'event_id boş olamaz';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || ':' || p_event_id));

    SELECT * INTO v_cached
    FROM public.processed_events
    WHERE user_id = v_user_id AND event_id = p_event_id;

    IF FOUND THEN
        RETURN v_cached.result_json || jsonb_build_object('duplicate', true);
    END IF;

    -- Geçersiz veri sınırları
    IF p_distance_km IS NULL OR p_distance_km <= 0 OR p_distance_km > 300 OR p_distance_km != p_distance_km
       OR p_avg_speed_kmh IS NULL OR p_avg_speed_kmh < 0
       OR p_max_speed_kmh IS NULL OR p_max_speed_kmh < 0 THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Geçersiz sürüş verisi.');
    END IF;

    -- KAPISI 1: Hız Reddi (max >= 50 km/sa VEYA ortalama >= 35 km/sa)
    -- Puan verilmez, Utanç Tablosu cezası UYGULANMAZ (hız hilesi reddidir)
    IF p_is_spoof OR p_max_speed_kmh >= 50.0 OR p_avg_speed_kmh >= 35.0 THEN
        INSERT INTO public.activities (
            event_id, user_id, activity_type, distance_km,
            avg_speed_kmh, max_speed_kmh, accel_variance,
            points_earned, co2_delta_kg, verification_status,
            feedback_message, created_at
        ) VALUES (
            p_event_id, v_user_id, 'bike', p_distance_km,
            p_avg_speed_kmh, p_max_speed_kmh, p_accel_variance,
            0, 0.00, 'rejected_speed_spoof',
            COALESCE(p_reject_reason, '❌ Hız reddi: Saatte 50 km giden bisiklet olmaz! Aktivite reddedildi.'), NOW()
        );

        v_res := jsonb_build_object(
            'ok', false,
            'rejected', true,
            'reason', COALESCE(p_reject_reason, '❌ Hız reddi: Saatte 50 km giden bisiklet olmaz! Aktivite reddedildi (puan verilmedi, Utanç Tablosu cezası uygulanmadı).')
        );

    -- KAPISI 2: Araba Şüphesi (Hız > 25 km/sa ve İvme Varyansı < 0.12 - titreşimsiz pürüzsüz taşıt sürüşü)
    -- Aktivite puanı verilmez. Haftalık araba/taksi sayacına +1 eklenir ve mesafe × 0.192 kg harcanan CO₂ Utanç Tablosuna işlenir.
    ELSIF p_avg_speed_kmh > 25.0 AND p_accel_variance IS NOT NULL AND p_accel_variance >= 0 AND p_accel_variance < 0.12 THEN
        v_wasted_co2 := ROUND(p_distance_km * 0.192, 2);

        INSERT INTO public.activities (
            event_id, user_id, activity_type, distance_km,
            avg_speed_kmh, max_speed_kmh, accel_variance,
            points_earned, co2_delta_kg, verification_status,
            feedback_message, created_at
        ) VALUES (
            p_event_id, v_user_id, 'bike', p_distance_km,
            p_avg_speed_kmh, p_max_speed_kmh, p_accel_variance,
            0, -v_wasted_co2, 'shame_logged',
            '🚨 Araba şüphesi: Düşük titreşim varyansı (<0.12). Utanç Tablosuna yazıldı.', NOW()
        );

        UPDATE public.users
        SET weekly_car_taxi_trips = weekly_car_taxi_trips + 1,
            weekly_car_taxi_km = weekly_car_taxi_km + p_distance_km,
            weekly_wasted_co2_kg = weekly_wasted_co2_kg + v_wasted_co2,
            last_active_at = NOW()
        WHERE id = v_user_id
        RETURNING clan_id INTO v_clan_id;

        IF v_clan_id IS NOT NULL THEN
            UPDATE public.clans
            SET weekly_wasted_co2_kg = weekly_wasted_co2_kg + v_wasted_co2
            WHERE id = v_clan_id;
        END IF;

        v_res := jsonb_build_object(
            'ok', false,
            'penalty', true,
            'wasted_co2_kg', v_wasted_co2,
            'reason', '🚨 Araba şüphesi (titreşimsiz ivme: varyans < 0.12): Aktivite puanı verilmedi. Haftalık araba/taksi sayacına +1 eklendi ve ' || v_wasted_co2::TEXT || ' kg harcanan CO₂ Utanç Tablosu siciline işlendi.'
        );

    -- KAPISI 3: Geçerli Sürüş Onayı (Sunucu Puanı: FLOOR(km), Sunucu Tasarrufu: km × 0.19 kg)
    ELSE
        v_points := FLOOR(p_distance_km)::INT;
        v_co2_saved := ROUND(p_distance_km * 0.19, 2);

        INSERT INTO public.activities (
            event_id, user_id, activity_type, distance_km,
            avg_speed_kmh, max_speed_kmh, accel_variance,
            points_earned, co2_delta_kg, verification_status,
            feedback_message, created_at
        ) VALUES (
            p_event_id, v_user_id, 'bike', p_distance_km,
            p_avg_speed_kmh, p_max_speed_kmh, p_accel_variance,
            v_points, v_co2_saved, 'verified',
            'Bisiklet sürüşü onaylandı.', NOW()
        );

        UPDATE public.users
        SET weekly_points = weekly_points + v_points,
            all_time_points = all_time_points + v_points,
            weekly_saved_co2_kg = weekly_saved_co2_kg + v_co2_saved,
            last_active_at = NOW()
        WHERE id = v_user_id
        RETURNING clan_id INTO v_clan_id;

        IF v_clan_id IS NOT NULL THEN
            UPDATE public.clans
            SET weekly_points = weekly_points + v_points,
                all_time_points = all_time_points + v_points,
                weekly_saved_co2_kg = weekly_saved_co2_kg + v_co2_saved
            WHERE id = v_clan_id;
        END IF;

        v_res := jsonb_build_object(
            'ok', true,
            'points_awarded', v_points,
            'co2_saved_kg', v_co2_saved
        );
    END IF;

    INSERT INTO public.processed_events (user_id, event_id, event_type, result_json)
    VALUES (v_user_id, p_event_id, 'bike_session', v_res);

    RETURN v_res;
END;
$$;

-- 11. Araba / Taksi İsraf ve Utanç Tablosu Ceza Kaydı RPC (Son 45 Dk Transit Muafiyeti + 0.192kg)
CREATE OR REPLACE FUNCTION public.rpc_record_vehicle_penalty(
    p_event_id TEXT,
    p_distance_km NUMERIC,
    p_wasted_co2_kg NUMERIC DEFAULT NULL,
    p_avg_speed_kmh NUMERIC DEFAULT 0.00
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_cached RECORD;
    v_clan_id INT;
    v_is_exempt BOOLEAN := false;
    v_wasted NUMERIC(8,2);
    v_res JSONB;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    IF p_event_id IS NULL OR TRIM(p_event_id) = '' THEN
        RAISE EXCEPTION 'event_id boş olamaz';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || ':' || p_event_id));

    SELECT * INTO v_cached
    FROM public.processed_events
    WHERE user_id = v_user_id AND event_id = p_event_id;

    IF FOUND THEN
        RETURN v_cached.result_json || jsonb_build_object('duplicate', true);
    END IF;

    IF p_distance_km IS NULL OR p_distance_km <= 0 OR p_distance_km > 500 OR p_distance_km != p_distance_km THEN
        RAISE EXCEPTION 'Geçersiz mesafe ölçümü';
    END IF;

    -- Muafiyet Kapısı: Son 45 dk içinde toplu taşıma kaydı varsa ceza muafiyeti uygulanır
    SELECT EXISTS (
        SELECT 1 FROM public.transit_cooldowns
        WHERE user_id = v_user_id
          AND last_scanned_at >= NOW() - INTERVAL '45 minutes'
    ) INTO v_is_exempt;

    IF v_is_exempt THEN
        v_res := jsonb_build_object(
            'ok', true,
            'exempt', true,
            'message', 'Son 45 dk içinde toplu taşıma kaydın olduğu için araba/taksi muafiyeti devrede; ceza uygulanmadı.'
        );

        INSERT INTO public.processed_events (user_id, event_id, event_type, result_json)
        VALUES (v_user_id, p_event_id, 'vehicle_penalty', v_res);

        RETURN v_res;
    END IF;

    -- Sunucu Tarafı Harcanan CO₂: Mesafe × 0.192 kg/km
    v_wasted := ROUND(p_distance_km * 0.192, 2);

    -- Aktiviteye utanç kaydı yaz
    INSERT INTO public.activities (
        event_id, user_id, activity_type, distance_km,
        avg_speed_kmh, points_earned, co2_delta_kg,
        verification_status, feedback_message, created_at
    ) VALUES (
        p_event_id, v_user_id, 'car_taxi_penalty', p_distance_km,
        p_avg_speed_kmh, 0, -v_wasted,
        'shame_logged', 'Özel araç/taksi kullanımı tespit edildi. Utanç tablosuna işlendi.', NOW()
    );

    -- Kullanıcı ceza sayaçlarını artır
    UPDATE public.users
    SET weekly_car_taxi_trips = weekly_car_taxi_trips + 1,
        weekly_car_taxi_km = weekly_car_taxi_km + p_distance_km,
        weekly_wasted_co2_kg = weekly_wasted_co2_kg + v_wasted,
        last_active_at = NOW()
    WHERE id = v_user_id
    RETURNING clan_id INTO v_clan_id;

    -- Klan israf sayacını artır
    IF v_clan_id IS NOT NULL THEN
        UPDATE public.clans
        SET weekly_wasted_co2_kg = weekly_wasted_co2_kg + v_wasted
        WHERE id = v_clan_id;
    END IF;

    v_res := jsonb_build_object(
        'ok', true,
        'shame_logged', true,
        'wasted_co2_kg', v_wasted,
        'trips_added', 1
    );

    INSERT INTO public.processed_events (user_id, event_id, event_type, result_json)
    VALUES (v_user_id, p_event_id, 'vehicle_penalty', v_res);

    RETURN v_res;
END;
$$;

-- 12. Mağazadan Altın İle Kozmetik Satın Alma RPC (Atomik Bakiye ve Envanter Kontrolü)
CREATE OR REPLACE FUNCTION public.rpc_buy_shop_item(p_item_slug TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_item RECORD;
    v_user RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    -- Ürünü kontrol et
    SELECT * INTO v_item FROM public.shop_items WHERE item_slug = p_item_slug;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Mağaza ürünü bulunamadı: %', p_item_slug;
    END IF;

    -- Zaten sahip mi?
    IF EXISTS (SELECT 1 FROM public.user_inventory WHERE user_id = v_user_id AND item_slug = p_item_slug) THEN
        RAISE EXCEPTION 'Bu ürüne zaten sahipsiniz';
    END IF;

    -- Kullanıcının altını yeterli mi? (FOR UPDATE ile kilit)
    SELECT * INTO v_user FROM public.users WHERE id = v_user_id FOR UPDATE;
    IF v_user.gold_coins < v_item.price_gold THEN
        RAISE EXCEPTION 'Yetersiz altın! Gerekli: %, Mevcut: %', v_item.price_gold, v_user.gold_coins;
    END IF;

    -- Altını düş
    UPDATE public.users
    SET gold_coins = gold_coins - v_item.price_gold,
        last_active_at = NOW()
    WHERE id = v_user_id;

    -- Envantere ekle
    INSERT INTO public.user_inventory (user_id, item_slug)
    VALUES (v_user_id, p_item_slug);

    RETURN jsonb_build_object(
        'ok', true,
        'item_slug', p_item_slug,
        'price_paid', v_item.price_gold,
        'remaining_gold', v_user.gold_coins - v_item.price_gold
    );
END;
$$;

-- 13. Kozmetik Kuşanma (Equip) RPC
CREATE OR REPLACE FUNCTION public.rpc_equip_shop_item(p_item_slug TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_item RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    -- Çıkarma durumu (none veya default)
    IF p_item_slug IN ('none', 'frame_none', 'pet_none', 'default_avatar') THEN
        IF p_item_slug = 'default_avatar' THEN
            UPDATE public.users SET avatar_url = 'assets/avatars/user_sen.png' WHERE id = v_user_id;
        ELSIF p_item_slug LIKE '%frame%' OR p_item_slug = 'none' THEN
            UPDATE public.users SET frame_slug = 'none' WHERE id = v_user_id;
        ELSIF p_item_slug LIKE '%pet%' THEN
            UPDATE public.users SET pet_slug = 'none' WHERE id = v_user_id;
        END IF;
        RETURN jsonb_build_object('ok', true, 'equipped', p_item_slug);
    END IF;

    -- Envanter sahipliği kontrolü
    IF NOT EXISTS (SELECT 1 FROM public.user_inventory WHERE user_id = v_user_id AND item_slug = p_item_slug) THEN
        RAISE EXCEPTION 'Bu eşyaya henüz sahip değilsiniz';
    END IF;

    SELECT * INTO v_item FROM public.shop_items WHERE item_slug = p_item_slug;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bilinmeyen eşya kategorisi';
    END IF;

    IF v_item.category = 'avatar' THEN
        UPDATE public.users SET avatar_url = v_item.asset_preview WHERE id = v_user_id;
    ELSIF v_item.category = 'frame' THEN
        UPDATE public.users SET frame_slug = v_item.item_slug WHERE id = v_user_id;
    ELSIF v_item.category = 'pet' THEN
        UPDATE public.users SET pet_slug = v_item.item_slug WHERE id = v_user_id;
    END IF;

    RETURN jsonb_build_object('ok', true, 'category', v_item.category, 'equipped', p_item_slug);
END;
$$;

-- 14. Haftalık Sıfırlama ve Şampiyon Belirleme RPC (Idempotent: Haftada Yalnız 1 Kez)
CREATE OR REPLACE FUNCTION public.rpc_admin_trigger_weekly_reset()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_is_service_role BOOLEAN := false;
    v_week_id TEXT;
    v_week_label TEXT;
    v_top_user RECORD;
    v_top_clan RECORD;
    v_total_co2 NUMERIC(10,2);
    v_affected_users INT;
    v_affected_clans INT;
BEGIN
    -- Yetki kontrolü: server_admins tablosu VEYA service_role JWT rolü
    BEGIN
        v_is_service_role := ((current_setting('request.jwt.claims', true)::jsonb ->> 'role') = 'service_role');
    EXCEPTION WHEN OTHERS THEN
        v_is_service_role := false;
    END;

    IF NOT v_is_service_role AND (v_caller_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.server_admins WHERE user_id = v_caller_id)) THEN
        RAISE EXCEPTION 'Yetkisiz erişim: Bu işlem yalnızca sunucu yöneticileri tarafından yürütülebilir.';
    END IF;

    -- Haftalık Idempotency: Aynı hafta birden fazla kez sıfırlanamaz!
    v_week_id := TO_CHAR(NOW(), 'IYYY-"W"IW');

    IF EXISTS (SELECT 1 FROM public.weekly_champions WHERE week_id = v_week_id) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'already_settled', true,
            'message', 'Bu hafta (' || v_week_id || ') zaten sıfırlandı ve şampiyonlar ilan edildi.'
        );
    END IF;

    -- 1. Haftanın en yüksek puanlı bireysel şampiyonunu ve klanını sıfırlama ÖNCESİ belirle
    SELECT id, nickname, weekly_points INTO v_top_user
    FROM public.users
    ORDER BY weekly_points DESC, today_steps DESC
    LIMIT 1;

    SELECT id, name, weekly_points INTO v_top_clan
    FROM public.clans
    ORDER BY weekly_points DESC
    LIMIT 1;

    SELECT COALESCE(SUM(weekly_saved_co2_kg), 0) INTO v_total_co2 FROM public.clans;

    v_week_label := TO_CHAR(NOW() - INTERVAL '7 days', 'DD Mon') || ' - ' || TO_CHAR(NOW(), 'DD Mon YYYY') || ' Haftası';

    -- 2. Şampiyonlar vitrinine ekle
    INSERT INTO public.weekly_champions (
        week_id, week_label, champion_user_id, champion_user_points,
        champion_clan_id, champion_clan_points,
        total_community_saved_co2_kg, announced_at
    ) VALUES (
        v_week_id, v_week_label,
        v_top_user.id, COALESCE(v_top_user.weekly_points, 0),
        v_top_clan.id, COALESCE(v_top_clan.weekly_points, 0),
        v_total_co2, NOW()
    );

    -- 3. Kullanıcıların haftalık puanlarını Altına dönüştür ve haftalık sayaçları sıfırla
    -- NOT: Günlük adım ve streak korunur! Sadece haftalık alanlar sıfırlanır.
    UPDATE public.users
    SET gold_coins = gold_coins + weekly_points,
        weekly_points = 0,
        weekly_saved_co2_kg = 0,
        weekly_wasted_co2_kg = 0,
        weekly_car_taxi_trips = 0,
        weekly_car_taxi_km = 0;
    GET DIAGNOSTICS v_affected_users = ROW_COUNT;

    -- 4. Klanların haftalık puanlarını sıfırla
    UPDATE public.clans
    SET weekly_points = 0,
        weekly_saved_co2_kg = 0,
        weekly_wasted_co2_kg = 0;
    GET DIAGNOSTICS v_affected_clans = ROW_COUNT;

    RETURN jsonb_build_object(
        'ok', true,
        'week_id', v_week_id,
        'week_label', v_week_label,
        'champion_user', v_top_user.nickname,
        'champion_user_points', v_top_user.weekly_points,
        'champion_clan', v_top_clan.name,
        'champion_clan_points', v_top_clan.weekly_points,
        'total_community_saved_co2_kg', v_total_co2,
        'users_reset', v_affected_users,
        'clans_reset', v_affected_clans
    );
END;
$$;

-- 15. Admin Canlı Bildirim Gönderme RPC (Realtime Kuyruğuna Yazar)
CREATE OR REPLACE FUNCTION public.rpc_admin_send_notification(
    p_target_type TEXT,
    p_target_user_id UUID DEFAULT NULL,
    p_target_clan_id INT DEFAULT NULL,
    p_template_code TEXT DEFAULT NULL,
    p_title TEXT DEFAULT 'Bildirim',
    p_message_body TEXT DEFAULT '',
    p_severity TEXT DEFAULT 'savage'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_is_service_role BOOLEAN := false;
    v_new_id INT;
BEGIN
    BEGIN
        v_is_service_role := ((current_setting('request.jwt.claims', true)::jsonb ->> 'role') = 'service_role');
    EXCEPTION WHEN OTHERS THEN
        v_is_service_role := false;
    END;

    IF NOT v_is_service_role AND (v_caller_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.server_admins WHERE user_id = v_caller_id)) THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    INSERT INTO public.admin_notifications_log (
        target_type, target_user_id, target_clan_id,
        template_code, title, message_body, severity,
        is_delivered, created_at
    ) VALUES (
        p_target_type, p_target_user_id, p_target_clan_id,
        p_template_code, p_title, p_message_body, p_severity,
        true, NOW()
    )
    RETURNING id INTO v_new_id;

    RETURN jsonb_build_object('ok', true, 'notification_id', v_new_id);
END;
$$;

-- ============================================================================
-- GÜVENLİK YETKİLENDİRMELERİ (REVOKE & EXPLICIT GRANT)
-- En az yetki ilkesi: Admin ve sistem fonksiyonları authenticated/anon'a verilmez
-- ============================================================================
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM anon;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM authenticated;

-- Kamusal yardımcı fonksiyon
GRANT EXECUTE ON FUNCTION public.compute_league_tier(INT, VARCHAR) TO anon, authenticated;

-- Kullanıcı oturum RPC'leri (Authenticated Only)
GRANT EXECUTE ON FUNCTION public.rpc_sync_initial_profile TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_my_profile TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_update_profile TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_join_clan TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_record_steps TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_record_transit TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_record_bike TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_record_vehicle_penalty TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_buy_shop_item TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_equip_shop_item TO authenticated;

-- Yönetici ve Sistem RPC'leri (Yalnızca service_role / Edge Function yetkilidir!)
GRANT EXECUTE ON FUNCTION public.rpc_admin_trigger_weekly_reset TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_admin_send_notification TO service_role;
