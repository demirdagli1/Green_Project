-- ============================================================================
-- verification.sql
-- Canlı Supabase Dağıtım Sonrası Güvenli Doğrulama ve Assertion Test Paketi
-- Proje: Green_Project (fhaxxraibydsjikxacbb)
-- ============================================================================
-- DİKKAT: Bu test paketi tek bir açık BEGIN ... ROLLBACK transaction bloğunda çalışır.
-- Hiçbir COMMIT içermez; canlı demo veya kullanıcı verilerini asla kalıcı değiştirmez.
-- Gerçek fonksiyon ve güvenlik kapılarını sınar; hata durumunda EXCEPTION fırlatır.
-- ============================================================================

BEGIN;

-- 1. TABLO VE SEED VERİ SAYILARI ASSERTION DENETİMİ
DO $$
DECLARE
    v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count FROM public.leagues;
    IF v_count != 12 THEN
        RAISE EXCEPTION 'TEST 1 HATA: leagues tablosunda 12 kayıt bekleniyordu, % bulundu!', v_count;
    END IF;

    SELECT COUNT(*) INTO v_count FROM public.clans;
    IF v_count != 11 THEN
        RAISE EXCEPTION 'TEST 1 HATA: clans tablosunda 11 kayıt bekleniyordu, % bulundu!', v_count;
    END IF;

    SELECT COUNT(*) INTO v_count FROM public.users WHERE is_demo = true;
    IF v_count != 20 THEN
        RAISE EXCEPTION 'TEST 1 HATA: demo users tablosunda 20 kayıt bekleniyordu, % bulundu!', v_count;
    END IF;

    SELECT COUNT(*) INTO v_count FROM public.transit_stops;
    IF v_count != 6 THEN
        RAISE EXCEPTION 'TEST 1 HATA: transit_stops tablosunda 6 kayıt bekleniyordu, % bulundu!', v_count;
    END IF;

    SELECT COUNT(*) INTO v_count FROM public.shop_items;
    IF v_count != 8 THEN
        RAISE EXCEPTION 'TEST 1 HATA: shop_items tablosunda 8 kayıt bekleniyordu, % bulundu!', v_count;
    END IF;

    SELECT COUNT(*) INTO v_count FROM public.notification_templates;
    IF v_count != 6 THEN
        RAISE EXCEPTION 'TEST 1 HATA: notification_templates tablosunda 6 kayıt bekleniyordu, % bulundu!', v_count;
    END IF;

    SELECT COUNT(*) INTO v_count FROM public.weekly_champions;
    IF v_count < 1 THEN
        RAISE EXCEPTION 'TEST 1 HATA: weekly_champions tablosunda en az 1 kayıt bekleniyordu, % bulundu!', v_count;
    END IF;

    RAISE NOTICE 'TEST 1 BAŞARILI: Tablo ve seed verileri eksiksiz (12 lig, 11 klan, 20 demo kullanıcı, 6 durak, 8 mağaza) ✅';
END $$;

-- 2. LİG KADEMELERİNİN PUAN EŞİKLERİNE UYGUNLUĞU ASSERTION DENETİMİ
DO $$
DECLARE
    v_user_mismatch INT;
    v_clan_mismatch INT;
BEGIN
    SELECT COUNT(*) INTO v_user_mismatch
    FROM public.users
    WHERE league_tier != public.compute_league_tier(weekly_points, 'individual');

    IF v_user_mismatch > 0 THEN
        RAISE EXCEPTION 'TEST 2 HATA: % kullanıcı dinamik lig kademesiyle uyuşmuyor!', v_user_mismatch;
    END IF;

    SELECT COUNT(*) INTO v_clan_mismatch
    FROM public.clans
    WHERE league_tier != public.compute_league_tier(weekly_points, 'clan');

    IF v_clan_mismatch > 0 THEN
        RAISE EXCEPTION 'TEST 2 HATA: % klan dinamik lig kademesiyle uyuşmuyor!', v_clan_mismatch;
    END IF;

    RAISE NOTICE 'TEST 2 BAŞARILI: Tüm kullanıcı ve klanlar dinamik lig kademelerine tam uygun ✅';
END $$;

-- 3. RLS AKTİFLİK VE SÜTUN GİZLİLİK ASSERTION DENETİMİ
DO $$
DECLARE
    v_unprotected INT;
    v_leak_count INT;
    v_priv_leak INT;
BEGIN
    -- 13 tablonun tamamında RLS açık olmalıdır
    SELECT COUNT(*) INTO v_unprotected
    FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename IN (
        'leagues', 'clans', 'users', 'transit_stops', 'shop_items',
        'user_inventory', 'processed_events', 'transit_cooldowns',
        'activities', 'notification_templates', 'admin_notifications_log',
        'weekly_champions', 'server_admins'
      )
      AND rowsecurity = false;

    IF v_unprotected > 0 THEN
        RAISE EXCEPTION 'TEST 3 HATA: % tabloda RLS etkin değil!', v_unprotected;
    END IF;

    -- v_leaderboard_users görünümünde gizli alan bulunmamalıdır
    SELECT COUNT(*) INTO v_leak_count
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'v_leaderboard_users'
      AND column_name IN ('device_id', 'gold_coins', 'weekly_wasted_co2_kg', 'last_streak_date');

    IF v_leak_count > 0 THEN
        RAISE EXCEPTION 'TEST 3 HATA: v_leaderboard_users içine gizli sütun sızıyor! (% adet)', v_leak_count;
    END IF;

    -- users tablosunda device_id ve gold_coins kamuya/authenticated rolüne kapalı olmalıdır
    SELECT COUNT(*) INTO v_priv_leak
    FROM information_schema.column_privileges
    WHERE table_schema = 'public'
      AND table_name = 'users'
      AND grantee IN ('anon', 'authenticated', 'PUBLIC')
      AND column_name IN ('device_id', 'gold_coins')
      AND privilege_type = 'SELECT';

    IF v_priv_leak > 0 THEN
        RAISE EXCEPTION 'TEST 3 HATA: users tablosunda gizli sütun SELECT yetkisi açık! (% adet)', v_priv_leak;
    END IF;

    RAISE NOTICE 'TEST 3 BAŞARILI: RLS tüm tablolarda aktif, v_leaderboard_users ve users sütun gizliliği tam ✅';
END $$;

-- 4. İKİ FARKLI AUTH KİMLİĞİ ARASINDA SAHİPLİK İZOLASYONU VE PRIVATE KOLON RET
DO $$
DECLARE
    v_uid_a UUID := '99999999-9999-9999-9999-999999999901';
    v_uid_b UUID := '99999999-9999-9999-9999-999999999902';
    v_affected INT;
    v_read_count INT;
    v_inv_count INT;
    v_gold_read_failed BOOLEAN := false;
    v_device_read_failed BOOLEAN := false;
    v_star_read_failed BOOLEAN := false;
    v_test_gold INT;
    v_test_device TEXT;
    v_leaderboard_count INT;
    v_my_prof JSONB;
BEGIN
    -- İzole test kullanıcılarını hazırla
    DELETE FROM public.user_inventory WHERE user_id IN (v_uid_a, v_uid_b);
    DELETE FROM public.activities WHERE user_id IN (v_uid_a, v_uid_b);
    DELETE FROM public.transit_cooldowns WHERE user_id IN (v_uid_a, v_uid_b);
    DELETE FROM public.processed_events WHERE user_id IN (v_uid_a, v_uid_b);
    DELETE FROM public.users WHERE id IN (v_uid_a, v_uid_b);

    INSERT INTO public.users (id, device_id, nickname, gold_coins, is_demo)
    VALUES
        (v_uid_a, 'DEV-TEST-USER-A', 'User A', 1000, false),
        (v_uid_b, 'DEV-TEST-USER-B', 'User B', 2500, false);

    INSERT INTO public.user_inventory (user_id, item_slug)
    VALUES (v_uid_b, 'frame_oxygen_glow')
    ON CONFLICT DO NOTHING;

    -- Kullanıcı A oturumuna geç (authenticated JWT)
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_uid_a::text, 'role', 'authenticated')::text, true);

    -- 4.1. Kullanıcı A, Kullanıcı B'nin profilini güncelleyemez (RLS ret)
    UPDATE public.users SET bio = 'HACKED BY A' WHERE id = v_uid_b;
    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected > 0 THEN
        EXECUTE 'RESET ROLE';
        RAISE EXCEPTION 'TEST 4 HATA: Kullanıcı A, Kullanıcı B''nin profilini değiştirebildi! ❌';
    END IF;

    -- 4.2. Kullanıcı A, Kullanıcı B'nin aktivitelerini okuyamaz (RLS ret)
    SELECT COUNT(*) INTO v_read_count FROM public.activities WHERE user_id = v_uid_b;
    IF v_read_count > 0 THEN
        EXECUTE 'RESET ROLE';
        RAISE EXCEPTION 'TEST 4 HATA: Kullanıcı A, Kullanıcı B''nin aktivitelerini okuyabildi! ❌';
    END IF;

    -- 4.3. Kullanıcı A, Kullanıcı B'nin envanterini okuyamaz (RLS ret)
    SELECT COUNT(*) INTO v_inv_count FROM public.user_inventory WHERE user_id = v_uid_b;
    IF v_inv_count > 0 THEN
        EXECUTE 'RESET ROLE';
        RAISE EXCEPTION 'TEST 4 HATA: Kullanıcı A, Kullanıcı B''nin envanterini okuyabildi! ❌';
    END IF;

    -- 4.4. Kullanıcı A, doğrudan users tablosundan gold_coins okuyamaz (Kolon seviyesi ret)
    BEGIN
        EXECUTE 'SELECT gold_coins FROM public.users WHERE id = $1' INTO v_test_gold USING v_uid_b;
    EXCEPTION WHEN insufficient_privilege THEN
        v_gold_read_failed := true;
    WHEN OTHERS THEN
        v_gold_read_failed := true;
    END;
    IF NOT v_gold_read_failed THEN
        EXECUTE 'RESET ROLE';
        RAISE EXCEPTION 'TEST 4 HATA: Kullanıcı A başka kullanıcının gold_coins alanını okuyabildi! ❌';
    END IF;

    -- 4.5. Kullanıcı A, doğrudan users tablosundan device_id okuyamaz (Kolon seviyesi ret)
    BEGIN
        EXECUTE 'SELECT device_id FROM public.users WHERE id = $1' INTO v_test_device USING v_uid_b;
    EXCEPTION WHEN insufficient_privilege THEN
        v_device_read_failed := true;
    WHEN OTHERS THEN
        v_device_read_failed := true;
    END;
    IF NOT v_device_read_failed THEN
        EXECUTE 'RESET ROLE';
        RAISE EXCEPTION 'TEST 4 HATA: Kullanıcı A başka kullanıcının device_id alanını okuyabildi! ❌';
    END IF;

    -- 4.6. Kullanıcı A, users tablosu üzerinde SELECT * çalıştıramaz (Yetkisiz kolon ret)
    BEGIN
        EXECUTE 'SELECT * FROM public.users WHERE id = $1' USING v_uid_b;
    EXCEPTION WHEN insufficient_privilege THEN
        v_star_read_failed := true;
    WHEN OTHERS THEN
        v_star_read_failed := true;
    END;
    IF NOT v_star_read_failed THEN
        EXECUTE 'RESET ROLE';
        RAISE EXCEPTION 'TEST 4 HATA: Kullanıcı A, users tablosu üzerinde SELECT * çalıştırabildi! ❌';
    END IF;

    -- 4.7. Kullanıcı A, güvenli görünümden (v_leaderboard_users) kamu verilerini okur
    SELECT COUNT(*) INTO v_leaderboard_count FROM public.v_leaderboard_users;
    IF v_leaderboard_count < 2 THEN
        EXECUTE 'RESET ROLE';
        RAISE EXCEPTION 'TEST 4 HATA: v_leaderboard_users beklenen kayıtları döndüremedi! ❌';
    END IF;

    -- 4.8. Kullanıcı A, kendi altınını ve profilini dar RPC rpc_get_my_profile ile okur
    v_my_prof := public.rpc_get_my_profile();
    IF (v_my_prof ->> 'ok')::boolean != true OR (v_my_prof -> 'user' ->> 'gold_coins')::int != 1000 THEN
        EXECUTE 'RESET ROLE';
        RAISE EXCEPTION 'TEST 4 HATA: Kullanıcı kendi profilini rpc_get_my_profile ile okuyamadı! ❌';
    END IF;

    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    RAISE NOTICE 'TEST 4 BAŞARILI: İki kimlik sahiplik izolasyonu, kolon gizlilik retleri (gold_coins, device_id, SELECT *) ve dar RPC sahipliği doğrulandı ✅';
END $$;

-- 5. KISMİ ADIM (500 + 500 STEPS) VE OFFLINE MÜKERRER İŞLEM (DUPLICATE) KONTROLÜ
DO $$
DECLARE
    v_uid_a UUID := '99999999-9999-9999-9999-999999999901';
    v_res1 JSONB;
    v_res2 JSONB;
    v_res3 JSONB;
    v_steps_after INT;
    v_points_after INT;
BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_uid_a::text, 'role', 'authenticated')::text, true);

    -- 1. Çağrı: İlk 500 adım -> 1000 eşiği dolmadığı için 0 puan verilir, adım 500 olur
    v_res1 := public.rpc_record_steps('EVT-TEST-STEP-PART1', 500, 0.40);

    -- 2. Çağrı: İkinci 500 adım -> Toplam 1000 adıma ulaşır, sunucu 5 puan hesaplar
    v_res2 := public.rpc_record_steps('EVT-TEST-STEP-PART2', 500, 0.40);

    -- 3. Çağrı: İkinci çağrının aynı event_id ile mükerrer gönderimi -> duplicate = true
    v_res3 := public.rpc_record_steps('EVT-TEST-STEP-PART2', 500, 0.40);

    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);

    SELECT today_steps, weekly_points INTO v_steps_after, v_points_after
    FROM public.users WHERE id = v_uid_a;

    -- Assertions
    IF (v_res1 ->> 'ok')::boolean != true
       OR (v_res1 ->> 'duplicate')::boolean != false
       OR (v_res1 ->> 'points_awarded')::int != 0
       OR (v_res1 ->> 'today_steps')::int != 500 THEN
        RAISE EXCEPTION 'TEST 5 HATA: İlk kısmi 500 adım puanlama hatası! res1=% ❌', v_res1;
    END IF;

    IF (v_res2 ->> 'ok')::boolean != true
       OR (v_res2 ->> 'duplicate')::boolean != false
       OR (v_res2 ->> 'points_awarded')::int != 5
       OR (v_res2 ->> 'today_steps')::int != 1000 THEN
        RAISE EXCEPTION 'TEST 5 HATA: İkinci kısmi 500 adım eşik tamamlama puan hatası! res2=% ❌', v_res2;
    END IF;

    IF (v_res3 ->> 'duplicate')::boolean != true THEN
        RAISE EXCEPTION 'TEST 5 HATA: Mükerrer çağrı duplicate kilit kapısına takılmadı! res3=% ❌', v_res3;
    END IF;

    IF v_steps_after != 1000 OR v_points_after != 5 THEN
        RAISE EXCEPTION 'TEST 5 HATA: Kullanıcı nihai adım veya puan durumu hatalı! steps=%, points=% ❌',
            v_steps_after, v_points_after;
    END IF;

    RAISE NOTICE 'TEST 5 BAŞARILI: Kısmi 500+500 adım sunucu eşik puanlaması ve mükerrer event engellemesi doğrulandı ✅';
END $$;

-- 6. 45 DAKİKA COOLDOWN VE KANONİK DURAK (QR/NFC) ORTAK EŞLEŞME TESTİ
DO $$
DECLARE
    v_uid_a UUID := '99999999-9999-9999-9999-999999999901';
    v_res1 JSONB;
    v_res2 JSONB;
BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_uid_a::text, 'role', 'authenticated')::text, true);

    -- 1. Okutma: Durak QR URI payload'ı ile (KTU Durağı: TRB-KTU-01)
    v_res1 := public.rpc_record_transit('EVT-TEST-TR-01', 'YESILADIM://TRANSIT/TRB-KTU-01?sig=9f8a7b', 'QR');

    -- 2. Okutma: Hemen ardından AYNI kanonik durağın NFC UID'si ile ('04:A1:2B:9C:11:80:01')
    v_res2 := public.rpc_record_transit('EVT-TEST-TR-02', '04:A1:2B:9C:11:80:01', 'NFC');

    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);

    IF (v_res1 ->> 'ok')::boolean != true THEN
        RAISE EXCEPTION 'TEST 6 HATA: İlk QR biniş kaydı başarısız oldu! res1=% ❌', v_res1;
    END IF;

    IF (v_res2 ->> 'ok')::boolean != false
       OR (v_res2 ->> 'cooldown')::boolean != true
       OR (v_res2 ->> 'remaining_seconds')::int <= 0
       OR (v_res2 ->> 'remaining_seconds')::int > 2700 THEN
        RAISE EXCEPTION 'TEST 6 HATA: 45 dk cooldown ve ortak kanonik durak QR/NFC kuralı çalışmadı! res2=% ❌', v_res2;
    END IF;

    RAISE NOTICE 'TEST 6 BAŞARILI: 45 dakika ortak cooldown ve kanonik QR/NFC durak eşleşmesi doğrulandı ✅';
END $$;

-- 7. HIZ VE İVME DOĞRULAMA KAPILARI (BİSİKLET VE UTANÇ SAYAÇLARI)
DO $$
DECLARE
    v_uid_a UUID := '99999999-9999-9999-9999-999999999901';
    v_bike_spoof JSONB;
    v_bike_car JSONB;
    v_bike_ok JSONB;
    v_trips INT;
    v_wasted NUMERIC;
BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_uid_a::text, 'role', 'authenticated')::text, true);

    -- 1. Aşırı Hız Reddi (max >= 50 km/sa)
    v_bike_spoof := public.rpc_record_bike(
        'EVT-TEST-BIKE-SPOOF', 10.0, 32.0, 54.0, 0.450
    );

    -- 2. Araba Şüphesi Kapısı (hız > 25 km/sa ve titreşimsiz ivme varyansı < 0.12)
    v_bike_car := public.rpc_record_bike(
        'EVT-TEST-BIKE-CAR', 10.0, 28.0, 32.0, 0.080
    );

    -- 3. Geçerli Bisiklet Sürüşü (10.5 km -> 10 puan, 2.00 kg CO2)
    v_bike_ok := public.rpc_record_bike(
        'EVT-TEST-BIKE-OK', 10.5, 18.0, 24.0, 0.350
    );

    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);

    SELECT weekly_car_taxi_trips, weekly_wasted_co2_kg INTO v_trips, v_wasted
    FROM public.users WHERE id = v_uid_a;

    IF (v_bike_spoof ->> 'rejected')::boolean != true THEN
        RAISE EXCEPTION 'TEST 7 HATA: 50 km/sa üzeri sürüş reddedilmedi! ❌';
    END IF;

    IF (v_bike_car ->> 'penalty')::boolean != true OR (v_bike_car ->> 'wasted_co2_kg')::numeric != 1.92 THEN
        RAISE EXCEPTION 'TEST 7 HATA: Düşük varyanslı sürüş utanç tablosu cezası almadı! ❌';
    END IF;

    IF (v_bike_ok ->> 'ok')::boolean != true
       OR (v_bike_ok ->> 'points_awarded')::int != 10
       OR (v_bike_ok ->> 'co2_saved_kg')::numeric != 2.00 THEN
        RAISE EXCEPTION 'TEST 7 HATA: Geçerli bisiklet sürüşü puanı veya tasarrufu hatalı! res=% ❌', v_bike_ok;
    END IF;

    IF v_trips != 1 OR v_wasted != 1.92 THEN
        RAISE EXCEPTION 'TEST 7 HATA: Utanç tablosu sayaçları kullanıcı tablosuna yazılmadı! trips=%, wasted=% ❌',
            v_trips, v_wasted;
    END IF;

    RAISE NOTICE 'TEST 7 BAŞARILI: Bisiklet hız/varyans/araba doğrulama kapıları ve utanç sayaçları doğrulandı ✅';
END $$;

-- 8. ATOMİK MAĞAZA SATIN ALMA, ENVANTER VE KUŞANMA (ATOMIKSTORE)
DO $$
DECLARE
    v_uid_a UUID := '99999999-9999-9999-9999-999999999901';
    v_buy_res JSONB;
    v_equip_res JSONB;
    v_unowned_failed BOOLEAN := false;
    v_rebuy_failed BOOLEAN := false;
    v_user_gold INT;
    v_user_frame TEXT;
BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_uid_a::text, 'role', 'authenticated')::text, true);

    -- 1. 450 altınlık Oksijen Çerçevesini al (Bakiye 1000 -> 550)
    v_buy_res := public.rpc_buy_shop_item('frame_oxygen_glow');

    -- 2. Çerçeveyi kuşan
    v_equip_res := public.rpc_equip_shop_item('frame_oxygen_glow');

    -- 3. Sahip olunmayan bir eşyayı kuşanmayı dene (Hata fırlatmalıdır)
    BEGIN
        PERFORM public.rpc_equip_shop_item('frame_biosfer_gold');
    EXCEPTION WHEN OTHERS THEN
        v_unowned_failed := true;
    END;

    -- 4. Zaten sahip olunan eşyayı tekrar almayı dene (Hata fırlatmalıdır)
    BEGIN
        PERFORM public.rpc_buy_shop_item('frame_oxygen_glow');
    EXCEPTION WHEN OTHERS THEN
        v_rebuy_failed := true;
    END;

    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);

    SELECT gold_coins, frame_slug INTO v_user_gold, v_user_frame
    FROM public.users WHERE id = v_uid_a;

    IF (v_buy_res ->> 'ok')::boolean != true OR (v_buy_res ->> 'price_paid')::int != 450 THEN
        RAISE EXCEPTION 'TEST 8 HATA: Mağaza satın alma yanıtı hatalı! res=% ❌', v_buy_res;
    END IF;

    IF (v_equip_res ->> 'ok')::boolean != true THEN
        RAISE EXCEPTION 'TEST 8 HATA: Eşya kuşanma yanıtı hatalı! res=% ❌', v_equip_res;
    END IF;

    IF NOT v_unowned_failed THEN
        RAISE EXCEPTION 'TEST 8 HATA: Sahip olunmayan eşya kuşanma kapısından geçebildi! ❌';
    END IF;

    IF NOT v_rebuy_failed THEN
        RAISE EXCEPTION 'TEST 8 HATA: Sahip olunan eşya ikinci kez mükerrer satın alınabildi! ❌';
    END IF;

    IF v_user_gold != 550 OR v_user_frame != 'frame_oxygen_glow' THEN
        RAISE EXCEPTION 'TEST 8 HATA: Kullanıcı bakiye veya kuşanılan çerçeve uyuşmazlığı! gold=%, frame=% ❌',
            v_user_gold, v_user_frame;
    END IF;

    RAISE NOTICE 'TEST 8 BAŞARILI: Atomik altın düşüşü, mükerrer alım engeli ve envanter kuşanma kontrolü kusursuz ✅';
END $$;

-- 9. YÖNETİCİ KONTROLÜ VE HAFTALIK RESET IDEMPOTENCY TESTİ (HAFTARESET IDEMPOTENCY)
DO $$
DECLARE
    v_uid_a UUID := '99999999-9999-9999-9999-999999999901';
    v_unauth_blocked BOOLEAN := false;
    v_admin_res1 JSONB;
    v_admin_res2 JSONB;
    v_curr_week TEXT := TO_CHAR(NOW(), 'IYYY-"W"IW');
BEGIN
    -- 1. Yetkisiz authenticated kullanıcı haftalık sıfırlama çağıramaz
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_uid_a::text, 'role', 'authenticated')::text, true);

    BEGIN
        PERFORM public.rpc_admin_trigger_weekly_reset();
    EXCEPTION WHEN insufficient_privilege THEN
        v_unauth_blocked := true;
    WHEN OTHERS THEN
        v_unauth_blocked := true;
    END;

    IF NOT v_unauth_blocked THEN
        EXECUTE 'RESET ROLE';
        RAISE EXCEPTION 'TEST 9 HATA: Normal kullanıcı admin fonksiyonunu çalıştırabildi! ❌';
    END IF;

    -- 2. Service Role (Admin) yetkisiyle haftalık sıfırlama idempotency testi
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', jsonb_build_object('role', 'service_role')::text, true);

    -- Test transaction içinde mevcut hafta kaydı varsa temizle (seed W43 etkilenmez)
    DELETE FROM public.weekly_champions WHERE week_id = v_curr_week;

    -- 1. Sıfırlama çağrısı: Başarılı olmalı ve şampiyon kaydı oluşturmalı
    v_admin_res1 := public.rpc_admin_trigger_weekly_reset();

    -- 2. Sıfırlama çağrısı: Aynı hafta içinde ikinci kez çalıştırıldığında already_settled dönmeli
    v_admin_res2 := public.rpc_admin_trigger_weekly_reset();

    PERFORM set_config('request.jwt.claims', '', true);

    IF (v_admin_res1 ->> 'ok')::boolean != true OR (v_admin_res1 ->> 'week_id') IS NULL THEN
        RAISE EXCEPTION 'TEST 9 HATA: Haftalık sıfırlama 1. çağrı başarısız! res1=% ❌', v_admin_res1;
    END IF;

    IF (v_admin_res2 ->> 'ok')::boolean != false OR (v_admin_res2 ->> 'already_settled')::boolean != true THEN
        RAISE EXCEPTION 'TEST 9 HATA: Haftalık sıfırlama idempotency kapısı çalışmadı! res2=% ❌', v_admin_res2;
    END IF;

    RAISE NOTICE 'TEST 9 BAŞARILI: Admin yetki denetimi ve haftalık sıfırlama idempotency kapısı doğrulandı (Değişiklikler transaction sonunda geri alınacak) ✅';
END $$;

-- 10. DEMO VERİ KORUMA DENETİMİ VE ROLLBACK
DO $$
DECLARE
    v_demo_count INT;
BEGIN
    SELECT COUNT(*) INTO v_demo_count FROM public.users WHERE is_demo = true;
    IF v_demo_count != 20 THEN
        RAISE EXCEPTION 'TEST 10 HATA: Demo kullanıcı sayısı bozuldu! Mevcut: % ❌', v_demo_count;
    END IF;

    RAISE NOTICE 'TEST 10 BAŞARILI: 20 demo kullanıcısı korundu. Tüm doğrulama assertionları başarıyla geçti ✅';
END $$;

-- TÜM DEĞİŞİKLİKLERİ GERİ AL: VERİTABANI BAŞLANGIÇTAKİ ÖZGÜN HALİNE DÖNER, SIFIR ARTIK VERİ
ROLLBACK;
