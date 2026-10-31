-- ============================================================================
-- preflight_delivery.sql
-- Yeşil Adım — 09 DDL ve Canlı Doğrulama Preflight Paketi
-- Proje: Green_Project (fhaxxraibydsjikxacbb)
--
-- Root tarafından Supabase Dashboard SQL Editöründe tek seferde çalıştırılır.
-- AÇIK BEGIN ... ROLLBACK İÇİNDE ÇALIŞIR: Canlı veritabanını ASLA değiştirmez!
-- ============================================================================

BEGIN;

-- ============================================================================
-- AŞAMA 1: 09 DDL FONKSİYON TANIMI (INLINE MIGRATION DDL)
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


-- ============================================================================
-- AŞAMA 2: TESTLER VE DOĞRULAMA (ROLLBACK İLE ÇALIŞIR)
-- ============================================================================

-- TEST 1: TRANSIT GİRDİ DOĞRULAMA VE WILDCARD KORUMASI TESTLERİ
DO $$
DECLARE
    v_user_id UUID := gen_random_uuid();
    v_res JSONB;
BEGIN
    INSERT INTO public.users (id, device_id, nickname, weekly_points, is_demo)
    VALUES (v_user_id, 'test_dev_preflight_input', 'PreflightTester', 10, false);

    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_user_id);
    EXECUTE 'SET LOCAL role = authenticated';

    -- 1.1 Boş string p_stop_code reddedilmeli
    v_res := public.rpc_record_transit('evt_pf_empty', '');
    IF (v_res->>'ok')::BOOLEAN != false THEN
        RAISE EXCEPTION 'TEST 1.1 HATA: Boş durak kodu kabul edildi! Sonuç: %', v_res;
    END IF;

    -- 1.2 Sadece boşluk '   ' reddedilmeli
    v_res := public.rpc_record_transit('evt_pf_spaces', '   ');
    IF (v_res->>'ok')::BOOLEAN != false THEN
        RAISE EXCEPTION 'TEST 1.2 HATA: Sadece boşluk kodu kabul edildi! Sonuç: %', v_res;
    END IF;

    -- 1.3 Tek yüzde jokeri '%' reddedilmeli
    v_res := public.rpc_record_transit('evt_pf_percent', '%');
    IF (v_res->>'ok')::BOOLEAN != false THEN
        RAISE EXCEPTION 'TEST 1.3 HATA: Tek yüzde jokeri kabul edildi! Sonuç: %', v_res;
    END IF;

    -- 1.4 Çoklu yüzde '%%%' jokeri reddedilmeli (Wildcard injection engeli)
    v_res := public.rpc_record_transit('evt_pf_multi_percent', '%%%');
    IF (v_res->>'ok')::BOOLEAN != false THEN
        RAISE EXCEPTION 'TEST 1.4 HATA: Çoklu yüzde jokeri durak seçti! Sonuç: %', v_res;
    END IF;

    -- 1.5 Alt tire jokeri '_' reddedilmeli
    v_res := public.rpc_record_transit('evt_pf_underscore', '_');
    IF (v_res->>'ok')::BOOLEAN != false THEN
        RAISE EXCEPTION 'TEST 1.5 HATA: Alt tire jokeri kabul edildi! Sonuç: %', v_res;
    END IF;

    -- 1.6 Eksik URI 'YESILADIM://TRANSIT/' reddedilmeli
    v_res := public.rpc_record_transit('evt_pf_empty_uri', 'YESILADIM://TRANSIT/');
    IF (v_res->>'ok')::BOOLEAN != false THEN
        RAISE EXCEPTION 'TEST 1.6 HATA: Eksik URI kabul edildi! Sonuç: %', v_res;
    END IF;

    -- 1.7 Bilinmeyen durak reddedilmeli
    v_res := public.rpc_record_transit('evt_pf_unknown', 'GEÇERSİZ_DURAK_999');
    IF (v_res->>'ok')::BOOLEAN != false THEN
        RAISE EXCEPTION 'TEST 1.7 HATA: Bilinmeyen durak reddedilmedi! Sonuç: %', v_res;
    END IF;

    RESET ROLE;
    RAISE NOTICE 'PREFLIGHT TEST 1: Girdi doğrulama ve wildcard koruması PASS ✅';
END $$;


-- TEST 2: TRANSIT COOLDOWN VE ŞEMA SÖZLEŞMESİ (44:59 RET, 45:00 KABUL)
DO $$
DECLARE
    v_user_id UUID := gen_random_uuid();
    v_res JSONB;
    v_pts_before INT;
    v_pts_after INT;
    v_co2_before NUMERIC(8,2);
    v_co2_after NUMERIC(8,2);
    v_stop_co2 NUMERIC(8,2);
    v_stop_pts INT;
BEGIN
    -- TRB-KTU-01 durak ödüllerini DB tablosundan oku
    SELECT points_reward, co2_saved_per_trip_kg INTO v_stop_pts, v_stop_co2
    FROM public.transit_stops WHERE stop_code = 'TRB-KTU-01';

    INSERT INTO public.users (id, device_id, nickname, weekly_points, weekly_saved_co2_kg, is_demo)
    VALUES (v_user_id, 'test_dev_preflight_cd', 'PreflightCdTester', 50, 5.00, false);

    -- 2.1 44 dakika 59 saniye önce taranmış durak -> RET (Cooldown aktif)
    INSERT INTO public.transit_cooldowns (user_id, stop_code, last_scanned_at)
    VALUES (v_user_id, 'TRB-KTU-01', NOW() - INTERVAL '44 minutes 59 seconds');

    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_user_id);
    EXECUTE 'SET LOCAL role = authenticated';

    v_res := public.rpc_record_transit('evt_pf_cd_4459', 'TRB-KTU-01');
    IF (v_res->>'ok')::BOOLEAN != false OR (v_res->>'cooldown')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 2.1 HATA: 44:59 cooldown reddedilmeliydi! Sonuç: %', v_res;
    END IF;

    -- 2.2 Tam 45 dakika 00 saniye önce taranmış durak -> KABUL
    RESET ROLE;
    UPDATE public.transit_cooldowns
    SET last_scanned_at = NOW() - INTERVAL '45 minutes 00 seconds'
    WHERE user_id = v_user_id AND stop_code = 'TRB-KTU-01';

    SELECT weekly_points, weekly_saved_co2_kg INTO v_pts_before, v_co2_before
    FROM public.users WHERE id = v_user_id;

    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_user_id);
    EXECUTE 'SET LOCAL role = authenticated';

    v_res := public.rpc_record_transit('evt_pf_cd_4500', 'TRB-KTU-01');
    IF (v_res->>'ok')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 2.2 HATA: 45:00 süresi dolmuş durak kabul edilmeliydi! Sonuç: %', v_res;
    END IF;

    -- Şema kolonlarının (weekly_points, weekly_saved_co2_kg, last_active_at) hatasız güncellendiğini doğrula
    SELECT weekly_points, weekly_saved_co2_kg INTO v_pts_after, v_co2_after
    FROM public.users WHERE id = v_user_id;

    IF v_pts_after != (v_pts_before + v_stop_pts) THEN
        RAISE EXCEPTION 'TEST 2.2 HATA: Puan artışı yanlış! Önce: %, Sonra: %, Beklenen Artış: %', v_pts_before, v_pts_after, v_stop_pts;
    END IF;

    -- Gerçek 01_schema NUMERIC(8,2) duyarlılığına uygun hesaplama
    IF v_co2_after != ROUND(v_co2_before + v_stop_co2, 2) THEN
        RAISE EXCEPTION 'TEST 2.2 HATA: weekly_saved_co2_kg artışı yanlış! Önce: %, Sonra: %, Beklenen Artış: %', v_co2_before, v_co2_after, v_stop_co2;
    END IF;

    RESET ROLE;
    RAISE NOTICE 'PREFLIGHT TEST 2: 44:59 ret, 45:00 kabul ve weekly_saved_co2_kg güncellemesi PASS ✅';
END $$;


-- TEST 3: KANONİK VE GEÇERLİ DURAK GİRİŞLERİ (GERÇEK SEED DURAKLARI İLE)
DO $$
DECLARE
    v_user_id UUID := gen_random_uuid();
    v_res JSONB;
    v_stop_uri RECORD;
    v_stop_nfc RECORD;
BEGIN
    -- Gerçek transit_stops tablosundan kayıtlı iki farklı durak dinamik seçilir
    SELECT stop_code, qr_payload INTO v_stop_uri
    FROM public.transit_stops
    WHERE qr_payload IS NOT NULL AND qr_payload != ''
    ORDER BY id ASC
    LIMIT 1;

    SELECT stop_code, nfc_uid INTO v_stop_nfc
    FROM public.transit_stops
    WHERE nfc_uid IS NOT NULL AND nfc_uid != '' AND stop_code != v_stop_uri.stop_code
    ORDER BY id ASC
    LIMIT 1;

    IF v_stop_uri.qr_payload IS NULL OR v_stop_nfc.nfc_uid IS NULL THEN
        RAISE EXCEPTION 'TEST 3 HATA: transit_stops tablosunda geçerli test durakları bulunamadı!';
    END IF;

    INSERT INTO public.users (id, device_id, nickname, weekly_points, is_demo)
    VALUES (v_user_id, 'test_dev_preflight_valid', 'PreflightValidTester', 0, false);

    -- Fixture kullanıcısının cooldownunu teste özel sıfırla (Canlı kullanıcılara dokunulmaz)
    DELETE FROM public.transit_cooldowns WHERE user_id = v_user_id;

    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_user_id);
    EXECUTE 'SET LOCAL role = authenticated';

    -- 3.1 Gerçek kayıtlı tam URI yükü ile biniş
    v_res := public.rpc_record_transit('evt_pf_uri_real', v_stop_uri.qr_payload);
    IF (v_res->>'ok')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 3.1 HATA: Gerçek URI yükü (%) reddedildi: %', v_stop_uri.qr_payload, v_res;
    END IF;

    -- 3.2 Farklı durağın gerçek NFC UID'si ile biniş
    v_res := public.rpc_record_transit('evt_pf_nfc_real', v_stop_nfc.nfc_uid);
    IF (v_res->>'ok')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 3.2 HATA: Gerçek NFC UID (%) reddedildi: %', v_stop_nfc.nfc_uid, v_res;
    END IF;

    RESET ROLE;
    RAISE NOTICE 'PREFLIGHT TEST 3: Gerçek URI (%) ve farklı durak NFC (%) PASS ✅', v_stop_uri.stop_code, v_stop_nfc.stop_code;
END $$;


-- TEST 4: EVRENSEL GM POZİTİF YETKİ, DENETİM İZİ VE İZOLASYON TESTLERİ
DO $$
DECLARE
    v_admin_id UUID := gen_random_uuid();
    v_target_id UUID := gen_random_uuid();
    v_unauth_id UUID := gen_random_uuid();
    v_res JSONB;
    v_target_gold INT;
    v_target_steps INT;
    v_has_audit BOOLEAN;
BEGIN
    INSERT INTO public.users (id, device_id, nickname, gold_coins, today_steps, weekly_points, is_demo)
    VALUES 
        (v_admin_id, 'test_pf_admin', 'PfAdmin', 100, 0, 0, false),
        (v_target_id, 'test_pf_target', 'PfTarget', 20, 1000, 10, false),
        (v_unauth_id, 'test_pf_unauth', 'PfUnauth', 10, 0, 0, false);

    -- 4.1 Yetkisiz Kullanıcı Denetimi: Standart kullanıcı GM eylemi çağıramaz
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_unauth_id);
    EXECUTE 'SET LOCAL role = authenticated';

    BEGIN
        v_res := public.rpc_universal_gm_action(
            v_target_id,
            'add_gold',
            '{"amount": 100}'::jsonb,
            'gm_pf_unauth'
        );
        RAISE EXCEPTION 'TEST 4.1 HATA: server_admins olmayan kullanıcı GM işlemi yapabildi!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Yetkisiz erişim: Sunucu yöneticisi%' THEN
            RAISE EXCEPTION 'TEST 4.1 HATA: Beklenmeyen hata mesajı: %', SQLERRM;
        END IF;
    END;

    -- 4.2 Yetkili Sunucu Yöneticisi Ataması ve Pozitif GM Eylemleri
    RESET ROLE;
    INSERT INTO public.server_admins (user_id, notes)
    VALUES (v_admin_id, 'Preflight Test Admin');

    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_admin_id);
    EXECUTE 'SET LOCAL role = authenticated';

    -- Pozitif Eylem 1: Hedef kullanıcıya altın ekleme
    v_res := public.rpc_universal_gm_action(
        v_target_id,
        'add_gold',
        '{"amount": 50}'::jsonb,
        'gm_pf_gold'
    );
    IF (v_res->>'ok')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 4.2 HATA: Yetkili GM altın ekleme başarısız: %', v_res;
    END IF;

    -- Pozitif Eylem 2: Hedef kullanıcıya adım ekleme
    v_res := public.rpc_universal_gm_action(
        v_target_id,
        'add_steps',
        '{"count": 2000}'::jsonb,
        'gm_pf_steps'
    );
    IF (v_res->>'ok')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 4.2 HATA: Yetkili GM adım ekleme başarısız: %', v_res;
    END IF;

    -- Pozitif Eylem 3: Hedef kullanıcının utanç mesaj kotasını sıfırlama
    v_res := public.rpc_universal_gm_action(
        v_target_id,
        'reset_shame_quota',
        '{}'::jsonb,
        'gm_pf_quota'
    );
    IF (v_res->>'ok')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 4.2 HATA: Yetkili GM utanç kotası sıfırlama başarısız: %', v_res;
    END IF;

    -- 4.3 Denetim İzi (Audit Trail) ve Hedef Durum Teyidi
    RESET ROLE;
    SELECT gold_coins, today_steps INTO v_target_gold, v_target_steps
    FROM public.users WHERE id = v_target_id;

    IF v_target_gold != 70 THEN
        RAISE EXCEPTION 'TEST 4.3 HATA: Altın mutasyonu yanlış! Beklenen: 70, Mevcut: %', v_target_gold;
    END IF;

    IF v_target_steps != 3000 THEN
        RAISE EXCEPTION 'TEST 4.3 HATA: Adım mutasyonu yanlış! Beklenen: 3000, Mevcut: %', v_target_steps;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.admin_audit_trail
        WHERE admin_user_id = v_admin_id AND idempotency_key = 'gm_pf_gold'
    ) INTO v_has_audit;

    IF NOT v_has_audit THEN
        RAISE EXCEPTION 'TEST 4.3 HATA: admin_audit_trail tablosunda işlem kaydı bulunamadı!';
    END IF;

    -- 4.4 Mahremiyet İlkesi: Standart kullanıcı doğrudan admin_audit_trail okuyamamalı
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_unauth_id);
    EXECUTE 'SET LOCAL role = authenticated';

    IF (SELECT COUNT(*) FROM public.admin_audit_trail) != 0 THEN
        RAISE EXCEPTION 'TEST 4.4 HATA: Standart kullanıcı admin_audit_trail okuyabildi, RLS ihlali!';
    END IF;

    RESET ROLE;
    RAISE NOTICE 'PREFLIGHT TEST 4: GM yetki, işlem, denetim izi ve mahremiyet PASS ✅';
END $$;


-- TEST 5: DORMANT OTOBÜS FONKSİYONU TESTİ
DO $$
DECLARE
    v_res JSONB;
BEGIN
    v_res := public.rpc_record_bus_trip(
        p_event_id := 'evt_pf_bus_dormant',
        p_distance_km := 5.0,
        p_bus_score := 85,
        p_confidence := 0.95
    );
    IF (v_res->>'ok')::BOOLEAN != false OR (v_res->>'dormant')::BOOLEAN != true OR (v_res->>'points_delta')::INT != 0 THEN
        RAISE EXCEPTION 'TEST 5 HATA: rpc_record_bus_trip dormant:true dönmedi! Sonuç: %', v_res;
    END IF;

    RAISE NOTICE 'PREFLIGHT TEST 5: Dormant otobüs motoru sözleşmesi PASS ✅';
END $$;

ROLLBACK; -- PREFLIGHT: Canlı veritabanında ASLA kalıcı değişiklik yapmaz!
