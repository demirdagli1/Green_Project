-- ============================================================================
-- verification_rev08.sql
-- Yeşil Adım — 08_transit_input_validation Doğrulama ve GM Pozitif Test Paketi
-- Proje: Green_Project (fhaxxraibydsjikxacbb)
-- Root tarafından Supabase SQL Editöründe tek seferde çalıştırılabilir.
-- AÇIK BEGIN ... ROLLBACK İÇİNDE ÇALIŞIR: Canlı veritabanını kalıcı değiştirmez!
-- ============================================================================

BEGIN;

-- 1. TRANSIT GİRDİ DOĞRULAMA VE WILDCARD KORUMASI TESTLERİ
DO $$
DECLARE
    v_user_id UUID := gen_random_uuid();
    v_res JSONB;
BEGIN
    -- Test kullanıcısı oluştur
    INSERT INTO public.users (id, device_id, nickname, weekly_points, is_demo)
    VALUES (v_user_id, 'test_dev_transit_08', 'TransitTester08', 10, false);

    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_user_id);
    EXECUTE 'SET LOCAL role = authenticated';

    -- Test 1.1: Boş string p_stop_code reddedilmeli
    v_res := public.rpc_record_transit('evt_val_empty', '');
    IF (v_res->>'ok')::BOOLEAN != false THEN
        RAISE EXCEPTION 'TEST 1.1 HATA: Boş durak kodu kabul edildi! Sonuç: %', v_res;
    END IF;

    -- Test 1.2: Sadece boşluk '   ' reddedilmeli
    v_res := public.rpc_record_transit('evt_val_spaces', '   ');
    IF (v_res->>'ok')::BOOLEAN != false THEN
        RAISE EXCEPTION 'TEST 1.2 HATA: Sadece boşluktan oluşan kod kabul edildi! Sonuç: %', v_res;
    END IF;

    -- Test 1.3: Tek joker karakteri '%' reddedilmeli
    v_res := public.rpc_record_transit('evt_val_percent', '%');
    IF (v_res->>'ok')::BOOLEAN != false THEN
        RAISE EXCEPTION 'TEST 1.3 HATA: Tek yüzde (%%) jokeri kabul edildi! Sonuç: %', v_res;
    END IF;

    -- Test 1.4: Çoklu joker karakteri '%%%' reddedilmeli (Wildcard injection engeli)
    v_res := public.rpc_record_transit('evt_val_multi_percent', '%%%');
    IF (v_res->>'ok')::BOOLEAN != false THEN
        RAISE EXCEPTION 'TEST 1.4 HATA: Çoklu yüzde (%%%%%%) jokeri durak eşleştirdi! Sonuç: %', v_res;
    END IF;

    -- Test 1.5: Alt tire '_' jokeri reddedilmeli
    v_res := public.rpc_record_transit('evt_val_underscore', '_');
    IF (v_res->>'ok')::BOOLEAN != false THEN
        RAISE EXCEPTION 'TEST 1.5 HATA: Alt tire jokeri kabul edildi! Sonuç: %', v_res;
    END IF;

    -- Test 1.6: Eksik URI 'YESILADIM://TRANSIT/' reddedilmeli
    v_res := public.rpc_record_transit('evt_val_empty_uri', 'YESILADIM://TRANSIT/');
    IF (v_res->>'ok')::BOOLEAN != false THEN
        RAISE EXCEPTION 'TEST 1.6 HATA: Eksik URI kabul edildi! Sonuç: %', v_res;
    END IF;

    -- Test 1.7: Var olmayan geçersiz durak kodu reddedilmeli
    v_res := public.rpc_record_transit('evt_val_unknown', 'GEÇERSİZ_DURAK_999');
    IF (v_res->>'ok')::BOOLEAN != false THEN
        RAISE EXCEPTION 'TEST 1.7 HATA: Bilinmeyen durak kodu reddedilmedi! Sonuç: %', v_res;
    END IF;

    RESET ROLE;
    RAISE NOTICE 'TEST 1 BAŞARILI: Boş, wildcard, eksik URI ve geçersiz durak girişleri reddedildi ✅';
END $$;


-- 2. TRANSIT COOLDOWN SINIR TESTLERİ (44:59 RET, 45:00 KABUL)
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
    VALUES (v_user_id, 'test_dev_cooldown_08', 'CooldownTester08', 50, 5.00, false);

    -- Test 2.1: 44 dakika 59 saniye önce taranmış durak -> RET (Cooldown aktif)
    INSERT INTO public.transit_cooldowns (user_id, stop_code, last_scanned_at)
    VALUES (v_user_id, 'TRB-KTU-01', NOW() - INTERVAL '44 minutes 59 seconds');

    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_user_id);
    EXECUTE 'SET LOCAL role = authenticated';

    v_res := public.rpc_record_transit('evt_cd_4459', 'TRB-KTU-01');
    IF (v_res->>'ok')::BOOLEAN != false OR (v_res->>'cooldown')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 2.1 HATA: 44:59 cooldown reddedilmeliydi! Sonuç: %', v_res;
    END IF;

    -- Test 2.2: Tam 45 dakika 00 saniye önce taranmış durak -> KABUL
    RESET ROLE;
    UPDATE public.transit_cooldowns
    SET last_scanned_at = NOW() - INTERVAL '45 minutes 00 seconds'
    WHERE user_id = v_user_id AND stop_code = 'TRB-KTU-01';

    SELECT weekly_points, weekly_saved_co2_kg INTO v_pts_before, v_co2_before
    FROM public.users WHERE id = v_user_id;

    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_user_id);
    EXECUTE 'SET LOCAL role = authenticated';

    v_res := public.rpc_record_transit('evt_cd_4500', 'TRB-KTU-01');
    IF (v_res->>'ok')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 2.2 HATA: 45:00 süresi dolmuş durak kabul edilmeliydi! Sonuç: %', v_res;
    END IF;

    SELECT weekly_points, weekly_saved_co2_kg INTO v_pts_after, v_co2_after
    FROM public.users WHERE id = v_user_id;

    IF v_pts_after != (v_pts_before + v_stop_pts) THEN
        RAISE EXCEPTION 'TEST 2.2 HATA: Puan artışı yanlış! Önce: %, Sonra: %, Beklenen: %', v_pts_before, v_pts_after, v_stop_pts;
    END IF;

    IF v_co2_after != ROUND(v_co2_before + v_stop_co2, 2) THEN
        RAISE EXCEPTION 'TEST 2.2 HATA: weekly_saved_co2_kg artışı yanlış! Önce: %, Sonra: %, Beklenen: %', v_co2_before, v_co2_after, v_stop_co2;
    END IF;

    RESET ROLE;
    RAISE NOTICE 'TEST 2 BAŞARILI: Transit cooldown sınırları (44:59 ret, 45:00 kabul) kesinlikle doğrulandı ✅';
END $$;


-- 3. KANONİK VE GEÇERLİ DURAK GİRİŞLERİ (GERÇEK SEED DURAKLARI İLE)
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
    VALUES (v_user_id, 'test_dev_valid_08', 'ValidTester08', 0, false);

    -- Fixture kullanıcısının cooldownunu teste özel sıfırla (Canlı kullanıcılara dokunulmaz)
    DELETE FROM public.transit_cooldowns WHERE user_id = v_user_id;

    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_user_id);
    EXECUTE 'SET LOCAL role = authenticated';

    -- Test 3.1: Gerçek kayıtlı tam URI yükü ile biniş
    v_res := public.rpc_record_transit('evt_val_uri_real', v_stop_uri.qr_payload);
    IF (v_res->>'ok')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 3.1 HATA: Gerçek URI yükü (%) reddedildi: %', v_stop_uri.qr_payload, v_res;
    END IF;

    -- Test 3.2: Farklı durağın gerçek NFC UID'si ile biniş
    v_res := public.rpc_record_transit('evt_val_nfc_real', v_stop_nfc.nfc_uid);
    IF (v_res->>'ok')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 3.2 HATA: Gerçek NFC UID (%) reddedildi: %', v_stop_nfc.nfc_uid, v_res;
    END IF;

    RESET ROLE;
    RAISE NOTICE 'TEST 3 BAŞARILI: Gerçek URI (%) ve farklı durak NFC (%) doğrulandı ✅', v_stop_uri.stop_code, v_stop_nfc.stop_code;
END $$;


-- 4. EVRENSEL GM POZİTİF YETKİ, DENETİM İZİ VE İZOLASYON TESTLERİ
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
    -- Test kullanıcıları oluştur
    INSERT INTO public.users (id, device_id, nickname, gold_coins, today_steps, weekly_points, is_demo)
    VALUES 
        (v_admin_id, 'test_admin_dev', 'TestAdmin08', 100, 0, 0, false),
        (v_target_id, 'test_target_dev', 'TestTarget08', 20, 1000, 10, false),
        (v_unauth_id, 'test_unauth_dev', 'TestUnauth08', 10, 0, 0, false);

    -- 4.1 Yetkisiz Kullanıcı Denetimi: Standart kullanıcı GM eylemi çağıramaz
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_unauth_id);
    EXECUTE 'SET LOCAL role = authenticated';

    BEGIN
        v_res := public.rpc_universal_gm_action(
            v_target_id,
            'add_gold',
            '{"amount": 100}'::jsonb,
            'gm_evt_unauth_08'
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
    VALUES (v_admin_id, 'Test Admin 08 Yetkili');

    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_admin_id);
    EXECUTE 'SET LOCAL role = authenticated';

    -- Pozitif Eylem 1: Hedef kullanıcıya altın ekleme
    v_res := public.rpc_universal_gm_action(
        v_target_id,
        'add_gold',
        '{"amount": 50}'::jsonb,
        'gm_evt_gold_08'
    );
    IF (v_res->>'ok')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 4.2 HATA: Yetkili GM altın ekleme başarısız: %', v_res;
    END IF;

    -- Pozitif Eylem 2: Hedef kullanıcıya adım ekleme
    v_res := public.rpc_universal_gm_action(
        v_target_id,
        'add_steps',
        '{"count": 2000}'::jsonb,
        'gm_evt_steps_08'
    );
    IF (v_res->>'ok')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 4.2 HATA: Yetkili GM adım ekleme başarısız: %', v_res;
    END IF;

    -- Pozitif Eylem 3: Hedef kullanıcının utanç mesaj kotasını sıfırlama
    v_res := public.rpc_universal_gm_action(
        v_target_id,
        'reset_shame_quota',
        '{}'::jsonb,
        'gm_evt_quota_08'
    );
    IF (v_res->>'ok')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 4.2 HATA: Yetkili GM utanç kotası sıfırlama başarısız: %', v_res;
    END IF;

    -- 4.3 Denetim İzi (Audit Trail) ve Hedef Durum Teyidi
    RESET ROLE;
    SELECT gold_coins, today_steps INTO v_target_gold, v_target_steps
    FROM public.users WHERE id = v_target_id;

    IF v_target_gold != 70 THEN -- Başlangıç 20 + 50 = 70
        RAISE EXCEPTION 'TEST 4.3 HATA: Altın mutasyonu yanlış! Beklenen: 70, Mevcut: %', v_target_gold;
    END IF;

    IF v_target_steps != 3000 THEN -- Başlangıç 1000 + 2000 = 3000
        RAISE EXCEPTION 'TEST 4.3 HATA: Adım mutasyonu yanlış! Beklenen: 3000, Mevcut: %', v_target_steps;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.admin_audit_trail
        WHERE admin_user_id = v_admin_id AND idempotency_key = 'gm_evt_gold_08'
    ) INTO v_has_audit;

    IF NOT v_has_audit THEN
        RAISE EXCEPTION 'TEST 4.3 HATA: admin_audit_trail tablosunda işlem kaydı bulunamadı!';
    END IF;

    -- 4.4 Mahremiyet İlkesi: Standart kullanıcı doğrudan admin_audit_trail okuyamamalı
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_unauth_id);
    EXECUTE 'SET LOCAL role = authenticated';

    IF (SELECT COUNT(*) FROM public.admin_audit_trail) != 0 THEN
        RAISE EXCEPTION 'TEST 4.4 HATA: Standart kullanıcı admin_audit_trail satırlarını okuyabildi, RLS ihlali!';
    END IF;

    RESET ROLE;
    RAISE NOTICE 'TEST 4 BAŞARILI: Evrensel GM yetkili işlem, denetim izi ve mahremiyet izolasyonu doğrulandı ✅';
END $$;

ROLLBACK; -- Kesinlikle kalıcı test mutasyonu bırakma!
