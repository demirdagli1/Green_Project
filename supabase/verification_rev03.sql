-- ============================================================================
-- verification_rev03.sql
-- Revizyon 03 Güvenli Doğrulama ve Assertion Test Paketi
-- Proje: Green_Project (fhaxxraibydsjikxacbb)
-- Root tarafından Supabase Dashboard SQL Editor üzerinden tek seferde çalıştırılabilir.
-- AÇIK BEGIN ... ROLLBACK İÇİNDE ÇALIŞIR: Canlı veritabanını kalıcı değiştirmez!
-- ============================================================================

BEGIN;

-- 1. TABLO, SÜTUN VE GÖRÜNÜM VARLIK VE İZİN KONTROLÜ
DO $$
DECLARE
    v_has_col BOOLEAN;
    v_count INT;
BEGIN
    -- clan_role kolonu kontrolü
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'clan_role'
    ) INTO v_has_col;

    IF NOT v_has_col THEN
        RAISE EXCEPTION 'TEST 1 HATA: users tablosunda clan_role kolonu bulunamadı!';
    END IF;

    -- v_clan_members görünümü kontrolü
    SELECT COUNT(*) INTO v_count FROM public.v_clan_members;
    RAISE NOTICE 'TEST 1.1: v_clan_members erişilebilir (% satır) ✅', v_count;

    -- v_worst_clans görünümü kontrolü
    SELECT COUNT(*) INTO v_count FROM public.v_worst_clans;
    RAISE NOTICE 'TEST 1.2: v_worst_clans erişilebilir (% satır) ✅', v_count;

    -- Utanç görünümleri kontrolü
    SELECT COUNT(*) INTO v_count FROM public.v_clan_shame_board;
    SELECT COUNT(*) INTO v_count FROM public.v_global_shame_board;
    RAISE NOTICE 'TEST 1.3: Utanç panoları security_invoker ile erişilebilir ✅';
END $$;


-- 2. UTANÇ DÜRTME MESAJI VE KOTA ATOMİKLİK TESTİ
DO $$
DECLARE
    v_sender_id UUID;
    v_target_id UUID;
    v_res JSONB;
    v_sender_gold INT;
BEGIN
    SELECT id INTO v_sender_id FROM public.users WHERE is_demo = false LIMIT 1;
    SELECT id INTO v_target_id FROM public.users WHERE is_demo = false AND id != v_sender_id LIMIT 1;

    IF v_sender_id IS NULL OR v_target_id IS NULL THEN
        v_sender_id := gen_random_uuid();
        v_target_id := gen_random_uuid();
        INSERT INTO public.users (id, device_id, nickname, gold_coins, is_demo)
        VALUES 
            (v_sender_id, 'test_dev_sender', 'TestGönderici', 100, false),
            (v_target_id, 'test_dev_target', 'TestHedef', 100, false);
    ELSE
        UPDATE public.users SET gold_coins = 100 WHERE id = v_sender_id;
    END IF;

    DELETE FROM public.shame_message_quotas WHERE user_id = v_sender_id;

    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_sender_id);
    EXECUTE 'SET LOCAL role = authenticated';

    -- 1. Gönderim: 10 altın düşmeli
    v_res := public.rpc_send_shame_message(
        v_target_id,
        'Taksiye bineceğine bisiklete binseydin!',
        'test_idemp_01'
    );

    IF (v_res->>'ok')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 2 HATA: 1. Utanç mesajı başarısız: %', v_res;
    END IF;

    -- Gizlilik Negatif Testi: Authenticated rol doğrudan users.gold_coins okuyamamalı (42501 permission denied almalı)
    BEGIN
        EXECUTE 'SELECT gold_coins FROM public.users WHERE id = ' || quote_literal(v_sender_id);
        RAISE EXCEPTION 'TEST 2 HATA: Authenticated kullanıcı doğrudan users.gold_coins okuyabildi, mahremiyet ihlali!';
    EXCEPTION 
        WHEN insufficient_privilege THEN
            NULL; -- Beklenen davranış: 42501 permission denied doğrulandı!
        WHEN OTHERS THEN
            IF SQLSTATE != '42501' THEN
                RAISE;
            END IF;
    END;

    -- Yasal Kullanıcı Profili RPC'si üzerinden altın bakiyesini doğrula
    v_sender_gold := (public.rpc_get_my_profile()->'user'->>'gold_coins')::INT;
    IF v_sender_gold != 90 THEN
        RAISE EXCEPTION 'TEST 2 HATA: Altın kesintisi 10 olmalıydı! Mevcut: %', v_sender_gold;
    END IF;

    -- Aynı idempotency key ile tekrar deneme (İdempotent yanıt, altın kesilmemeli!)
    v_res := public.rpc_send_shame_message(
        v_target_id,
        'Taksiye bineceğine bisiklete binseydin!',
        'test_idemp_01'
    );
    IF (v_res->>'duplicate')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 2 HATA: Idempotent tekrar duplicate:true dönmeliydi!';
    END IF;

    v_sender_gold := (public.rpc_get_my_profile()->'user'->>'gold_coins')::INT;
    IF v_sender_gold != 90 THEN
        RAISE EXCEPTION 'TEST 2 HATA: Idempotent çağrı tekrar altın kesti!';
    END IF;

    -- 2. Farklı idempotency key ile aynı gün 2. mesaj denemesi (KOTA ENGELİ!)
    v_res := public.rpc_send_shame_message(
        v_target_id,
        'İkinci mesajı gönderememeliyim',
        'test_idemp_02'
    );
    IF (v_res->>'ok')::BOOLEAN != false THEN
        RAISE EXCEPTION 'TEST 2 HATA: Günlük kota 2. mesajı engellemeliydi!';
    END IF;

    RESET ROLE;
    RAISE NOTICE 'TEST 2 BAŞARILI: Utanç mesajı 10 altın kesti, gizlilik korundu (42501 negatif test PASS), idempotency ve günlük 1 mesaj kotası doğrulandı ✅';
END $$;


-- 3. OTOBÜS DOĞRULAMA, KISA OTOBÜS CEZASI VE ORTAK SETTLEMENT UZLAŞTIRMA TESTİ
DO $$
DECLARE
    v_user_id UUID;
    v_res JSONB;
    v_pts_before INT;
    v_pts_after INT;
BEGIN
    SELECT id INTO v_user_id FROM public.users WHERE is_demo = false LIMIT 1;
    IF v_user_id IS NULL THEN
        v_user_id := gen_random_uuid();
        INSERT INTO public.users (id, device_id, nickname, weekly_points, is_demo)
        VALUES (v_user_id, 'test_bus_user', 'BusTester', 20, false);
    ELSE
        UPDATE public.users SET weekly_points = 20 WHERE id = v_user_id;
    END IF;

    DELETE FROM public.transit_cooldowns WHERE user_id = v_user_id;

    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_user_id);
    EXECUTE 'SET LOCAL role = authenticated';

    -- Test 3: Otomatik otobüs motoru ayrı dalda (.worktrees/automatic-bus) geliştirildiği için
    -- ana teslimatta rpc_record_bus_trip güvenli 'dormant' durum döndürmeli ve puan mutasyonu yapmamalıdır.
    SELECT weekly_points INTO v_pts_before FROM public.users WHERE id = v_user_id;

    v_res := public.rpc_record_bus_trip(
        p_event_id := 'test_bus_evt_dormant',
        p_distance_km := 5.2,
        p_bus_score := 85,
        p_confidence := 0.95,
        p_stop_code := 'TRB-KTU-01',
        p_explanation := 'Dormant otobüs testi'
    );

    IF (v_res->>'ok')::BOOLEAN != false OR (v_res->>'dormant')::BOOLEAN != true OR (v_res->>'points_delta')::INT != 0 THEN
        RAISE EXCEPTION 'TEST 3 HATA: rpc_record_bus_trip dormant:true ve points_delta:0 dönmeliydi! Sonuç: %', v_res;
    END IF;

    SELECT weekly_points INTO v_pts_after FROM public.users WHERE id = v_user_id;
    IF v_pts_after != v_pts_before THEN
        RAISE EXCEPTION 'TEST 3 HATA: Dormant otobüs çağrısı puan değiştirmemeliydi! Önce: %, Sonra: %', v_pts_before, v_pts_after;
    END IF;

    RESET ROLE;
    RAISE NOTICE 'TEST 3 BAŞARILI: Otomatik otobüs fonksiyonu güvenli dormant durumunda ve puan mutasyonsuz doğrulandı ✅';
END $$;


-- 4. EVRENSEL GM VE AUDIT TRAIL TESTİ
DO $$
DECLARE
    v_admin_id UUID := gen_random_uuid();
    v_target_id UUID;
    v_res JSONB;
BEGIN
    SELECT id INTO v_target_id FROM public.users LIMIT 1;

    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_admin_id);
    EXECUTE 'SET LOCAL role = authenticated';

    BEGIN
        v_res := public.rpc_universal_gm_action(
            v_target_id,
            'add_gold',
            '{"amount": 50}'::jsonb,
            'test_gm_unauth'
        );
        RAISE EXCEPTION 'TEST 4 HATA: server_admins olmayan kullanıcı RPC çağırabildi!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Yetkisiz erişim: Sunucu yöneticisi%' THEN
            RAISE EXCEPTION 'Beklenmeyen hata: %', SQLERRM;
        END IF;
    END;

    RESET ROLE; -- server_admins tablosuna ekleme yapmak için postgres rolüne dön
    INSERT INTO public.server_admins (user_id, notes)
    VALUES (v_admin_id, 'Test Admin');

    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_admin_id);
    EXECUTE 'SET LOCAL role = authenticated';

    v_res := public.rpc_universal_gm_action(
        v_target_id,
        'add_gold',
        '{"amount": 50}'::jsonb,
        'test_gm_auth_01'
    );

    IF (v_res->>'ok')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 4 HATA: Yetkili GM çağrısı başarısız: %', v_res;
    END IF;

    RESET ROLE; -- admin_audit_trail tablosunu denetlemek için postgres rolüne dön
    IF NOT EXISTS (SELECT 1 FROM public.admin_audit_trail WHERE admin_user_id = v_admin_id AND idempotency_key = 'test_gm_auth_01') THEN
        RAISE EXCEPTION 'TEST 4 HATA: admin_audit_trail kaydı oluşmadı!';
    END IF;

    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_admin_id);
    EXECUTE 'SET LOCAL role = authenticated';

    v_res := public.rpc_universal_gm_action(
        v_target_id,
        'reset_shame_quota',
        '{}'::jsonb,
        'test_gm_reset_quota'
    );
    IF (v_res->>'ok')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 4 HATA: reset_shame_quota başarısız: %', v_res;
    END IF;

    RESET ROLE;
    RAISE NOTICE 'TEST 4 BAŞARILI: Evrensel GM yetki kontrolü, audit trail ve kota sıfırlama doğrulandı ✅';
END $$;

ROLLBACK; -- Kesinlikle kalıcı test mutasyonu bırakma!
