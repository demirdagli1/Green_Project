-- ============================================================================
-- 09_transit_schema_fix.sql
-- Yeşil Adım — Toplu Taşıma Şema Kolon Uyumu ve Kesin Girdi Doğrulama Düzeltmesi
--
-- Düzeltmeler:
-- 1. 08 sürümünde sehven kullanılan ve şemada bulunmayan "prevented_co2_kg" ile "updated_at"
--    kolonları kaldırıldı. Gerçek 01_schema sözleşmesine tam uyumlu olarak:
--    - public.users: "weekly_saved_co2_kg" ve "last_active_at" güncellenir.
--    - public.clans: "weekly_saved_co2_kg" güncellenir (updated_at sütunu yoktur).
-- 2. Boş string (''), NULL, yalnızca boşluk veya <3 karakterli geçersiz girdiler doğrudan reddedilir.
-- 3. LIKE wildcard (% ve _) karakterlerinin durak aramasında joker olması engellendi;
--    yalnızca tam kanonik durak kodu (stop_code), NFC UID veya tam qr_payload ile
--    kesin eşitlik (=) üzerinden eşleşme yapılır.
-- 4. 45 dakikalık cooldown kuralı strictly son 45 dakika (last_scanned_at > NOW() - INTERVAL '45 minutes')
--    olarak çalışır: 44:59 RET, 45:00 KABUL.
-- ============================================================================

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
    -- 1. Kimlik Doğrulama
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    -- 2. event_id Doğrulama
    IF p_event_id IS NULL OR TRIM(p_event_id) = '' THEN
        RAISE EXCEPTION 'event_id boş olamaz';
    END IF;

    -- 3. Girdi Doğrulama: Boş, NULL, beyaz alan veya çok kısa durak kodu kontrolü
    v_raw_code := TRIM(COALESCE(p_stop_code, ''));
    IF v_raw_code = '' OR LENGTH(v_raw_code) < 3 THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Geçersiz veya boş durak kodu.');
    END IF;

    -- Advisory lock ile eşzamanlı istek kilidi
    PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || ':' || p_event_id));

    -- İdempotency kontrolü
    SELECT * INTO v_cached
    FROM public.processed_events
    WHERE user_id = v_user_id AND event_id = p_event_id;

    IF FOUND THEN
        RETURN v_cached.result_json || jsonb_build_object('duplicate', true);
    END IF;

    -- Kullanıcı satırını kilitle (Eşzamanlı yarış durumlarını engeller)
    SELECT * INTO v_user FROM public.users WHERE id = v_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kullanıcı bulunamadı';
    END IF;

    -- 4. Kanonik Durak Kodunu Çıkar (Wildcard'sız Güvenli Ayrıştırma)
    v_canonical_stop := v_raw_code;
    IF UPPER(v_canonical_stop) LIKE 'YESILADIM://TRANSIT/%' THEN
        v_canonical_stop := substring(v_canonical_stop from 21);
        IF position('?' in v_canonical_stop) > 0 THEN
            v_canonical_stop := split_part(v_canonical_stop, '?', 1);
        END IF;
        IF position('/' in v_canonical_stop) > 0 THEN
            v_canonical_stop := split_part(v_canonical_stop, '/', 1);
        END IF;
    ELSIF position('?' in v_canonical_stop) > 0 THEN
        v_canonical_stop := split_part(v_canonical_stop, '?', 1);
    END IF;
    v_canonical_stop := UPPER(TRIM(v_canonical_stop));

    IF v_canonical_stop = '' OR LENGTH(v_canonical_stop) < 3 THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Geçersiz durak kodu formatı.');
    END IF;

    -- 5. Kesin Eşitlik (Equality) ile Durak Sorgulama (Joker/Wildcard eşleşmesi engellendi)
    SELECT * INTO v_stop
    FROM public.transit_stops
    WHERE UPPER(stop_code) = v_canonical_stop
       OR UPPER(nfc_uid) = UPPER(v_raw_code)
       OR qr_payload = v_raw_code
       OR UPPER(stop_code) = UPPER(v_raw_code)
    LIMIT 1;

    IF v_stop.id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Geçersiz veya bilinmeyen durak kodu.');
    END IF;

    -- 6. Cooldown Kontrolü: Şartname gereği tam 45 DAKİKA
    -- 44:59 RET, 45:00 KABUL: Strictly son 45 dakika içinde taranmışsa reddedilir
    SELECT last_scanned_at INTO v_last_scan
    FROM public.transit_cooldowns
    WHERE user_id = v_user_id
      AND (stop_code = v_stop.stop_code OR stop_code = 'AUTO_BUS_TRIP')
      AND last_scanned_at > (NOW() - INTERVAL '45 minutes')
    ORDER BY last_scanned_at DESC
    LIMIT 1;

    IF v_last_scan IS NOT NULL THEN
        v_rem_sec := EXTRACT(EPOCH FROM (v_last_scan + INTERVAL '45 minutes' - NOW()))::INT;
        RETURN jsonb_build_object(
            'ok', false,
            'cooldown', true,
            'remaining_seconds', GREATEST(v_rem_sec, 0),
            'message', format('Toplu taşıma bekleme süresi aktif (Kalan süre: %s dakika).', CEIL(GREATEST(v_rem_sec, 0)::NUMERIC / 60.0))
        );
    END IF;

    -- Cooldown kaydını güncelle
    INSERT INTO public.transit_cooldowns (user_id, stop_code, last_scanned_at)
    VALUES (v_user_id, v_stop.stop_code, NOW())
    ON CONFLICT (user_id, stop_code)
    DO UPDATE SET last_scanned_at = NOW();

    -- Puan ve CO2 ödülünü kullanıcıya işle (01_schema sözleşmesi: weekly_saved_co2_kg, last_active_at)
    UPDATE public.users
    SET weekly_points = weekly_points + v_stop.points_reward,
        all_time_points = all_time_points + v_stop.points_reward,
        weekly_saved_co2_kg = weekly_saved_co2_kg + v_stop.co2_saved_per_trip_kg,
        last_active_at = NOW()
    WHERE id = v_user_id;

    -- Varsa klan puan ve CO2 değerini işle (01_schema sözleşmesi: weekly_saved_co2_kg)
    v_clan_id := v_user.clan_id;
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

REVOKE EXECUTE ON FUNCTION public.rpc_record_transit FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_record_transit TO authenticated;
