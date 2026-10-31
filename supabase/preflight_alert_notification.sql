-- ============================================================================
-- preflight_alert_notification.sql
-- Yeşil Adım — Migration 10 Preflight Doğrulama Paketi
--
-- Root tarafından Supabase Dashboard SQL Editöründe tek seferde çalıştırılır.
-- AÇIK BEGIN ... ROLLBACK İÇİNDE ÇALIŞIR: Canlı veritabanını ASLA değiştirmez!
--
-- Kapsam:
-- 1. Migration 10 inline DDL tanımı (rpc_universal_gm_action güncellemesi)
-- 2. Gerçek şemaya uygun izole users ve server_admins fixture'ları
-- 3. Yetkisiz standart kullanıcı ret testi
-- 4. Yetkili GM 'send_alert_notification' aksiyonu ve admin_notifications_log doğrulama
-- 5. Idempotency testi (aynı anahtarda tek bildirim ve tek audit kaydı teyidi)
-- 6. Sayısal GM aksiyonları (add_steps, add_gold, add_streak, add_points, reset_shame_quota) duman testi
-- ============================================================================

BEGIN;

-- ============================================================================
-- AŞAMA 1: MIGRATION 10 INLINE DDL
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_universal_gm_action(
    p_target_user_id UUID,
    p_action TEXT,
    p_payload JSONB,
    p_idempotency_key TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_admin_id UUID := auth.uid();
    v_target RECORD;
    v_amount INT;
    v_res JSONB;
    v_cached RECORD;
    v_today DATE := (CURRENT_TIMESTAMP AT TIME ZONE 'Europe/Istanbul')::date;
    v_title VARCHAR(120);
    v_body TEXT;
    v_admin_name VARCHAR(50);
BEGIN
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim: Giriş yapmadınız';
    END IF;

    -- server_admins kontrolü (user_metadata değil, veritabanı tablosu!)
    IF NOT EXISTS (SELECT 1 FROM public.server_admins WHERE user_id = v_admin_id) THEN
        RAISE EXCEPTION 'Yetkisiz erişim: Sunucu yöneticisi (server_admins) değilsiniz!';
    END IF;

    IF p_idempotency_key IS NULL OR TRIM(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'Idempotency anahtarı gereklidir';
    END IF;

    -- 1. Advisory Lock (Yarış durumu engeli)
    PERFORM pg_advisory_xact_lock(hashtext(v_admin_id::text || ':gm:' || p_idempotency_key));

    -- 2. Idempotency Kontrolü (Admin scope'lu)
    SELECT * INTO v_cached 
    FROM public.admin_audit_trail 
    WHERE admin_user_id = v_admin_id AND idempotency_key = p_idempotency_key;
    IF FOUND THEN
        RETURN v_cached.result_json || jsonb_build_object('duplicate', true);
    END IF;

    -- 3. Hedef Kullanıcı Kilidi (FOR UPDATE)
    SELECT * INTO v_target FROM public.users WHERE id = p_target_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Hedef kullanıcı bulunamadı');
    END IF;

    -- 4. Aksiyonlar ve Sayısal Aralık Doğrulamaları
    CASE p_action
        WHEN 'add_steps' THEN
            v_amount := (p_payload->>'count')::INT;
            IF v_amount IS NULL OR v_amount < 1 OR v_amount > 100000 THEN
                RETURN jsonb_build_object('ok', false, 'message', 'Adım miktarı 1 ile 100.000 arasında olmalıdır.');
            END IF;
            UPDATE public.users 
            SET today_steps = today_steps + v_amount,
                last_active_at = NOW()
            WHERE id = p_target_user_id;
            v_res := jsonb_build_object('ok', true, 'action', p_action, 'added', v_amount);

        WHEN 'set_steps' THEN
            v_amount := (p_payload->>'total')::INT;
            IF v_amount IS NULL OR v_amount < 0 OR v_amount > 1000000 THEN
                RETURN jsonb_build_object('ok', false, 'message', 'Toplam adım 0 ile 1.000.000 arasında olmalıdır.');
            END IF;
            UPDATE public.users 
            SET today_steps = v_amount,
                last_active_at = NOW()
            WHERE id = p_target_user_id;
            v_res := jsonb_build_object('ok', true, 'action', p_action, 'new_total', v_amount);

        WHEN 'add_streak' THEN
            v_amount := (p_payload->>'days')::INT;
            IF v_amount IS NULL OR v_amount < 1 OR v_amount > 365 THEN
                RETURN jsonb_build_object('ok', false, 'message', 'Seri gün sayısı 1 ile 365 arasında olmalıdır.');
            END IF;
            UPDATE public.users 
            SET streak_days = streak_days + v_amount,
                last_active_at = NOW()
            WHERE id = p_target_user_id;
            v_res := jsonb_build_object('ok', true, 'action', p_action, 'added_days', v_amount);

        WHEN 'set_streak' THEN
            v_amount := (p_payload->>'days')::INT;
            IF v_amount IS NULL OR v_amount < 0 OR v_amount > 365 THEN
                RETURN jsonb_build_object('ok', false, 'message', 'Seri gün sayısı 0 ile 365 arasında olmalıdır.');
            END IF;
            UPDATE public.users 
            SET streak_days = v_amount,
                last_active_at = NOW()
            WHERE id = p_target_user_id;
            v_res := jsonb_build_object('ok', true, 'action', p_action, 'new_days', v_amount);

        WHEN 'add_gold' THEN
            v_amount := (p_payload->>'amount')::INT;
            IF v_amount IS NULL OR v_amount < -100000 OR v_amount > 100000 THEN
                RETURN jsonb_build_object('ok', false, 'message', 'Altın miktarı -100.000 ile +100.000 arasında olmalıdır.');
            END IF;
            IF v_target.gold_coins + v_amount < 0 THEN
                RETURN jsonb_build_object('ok', false, 'message', 'Kullanıcının altını negatif olamaz.');
            END IF;
            UPDATE public.users 
            SET gold_coins = gold_coins + v_amount,
                last_active_at = NOW()
            WHERE id = p_target_user_id;
            v_res := jsonb_build_object('ok', true, 'action', p_action, 'added_gold', v_amount);

        WHEN 'set_gold' THEN
            v_amount := (p_payload->>'total')::INT;
            IF v_amount IS NULL OR v_amount < 0 OR v_amount > 1000000 THEN
                RETURN jsonb_build_object('ok', false, 'message', 'Toplam altın 0 ile 1.000.000 arasında olmalıdır.');
            END IF;
            UPDATE public.users 
            SET gold_coins = v_amount,
                last_active_at = NOW()
            WHERE id = p_target_user_id;
            v_res := jsonb_build_object('ok', true, 'action', p_action, 'new_gold', v_amount);

        WHEN 'add_points' THEN
            v_amount := (p_payload->>'points')::INT;
            IF v_amount IS NULL OR v_amount < -10000 OR v_amount > 10000 THEN
                RETURN jsonb_build_object('ok', false, 'message', 'Puan miktarı -10.000 ile +10.000 arasında olmalıdır.');
            END IF;
            UPDATE public.users 
            SET weekly_points = GREATEST(0, weekly_points + v_amount),
                all_time_points = GREATEST(0, all_time_points + v_amount),
                last_active_at = NOW()
            WHERE id = p_target_user_id;

            IF v_target.clan_id IS NOT NULL THEN
                UPDATE public.clans 
                SET weekly_points = GREATEST(0, weekly_points + v_amount),
                    all_time_points = GREATEST(0, all_time_points + v_amount)
                WHERE id = v_target.clan_id;
            END IF;
            v_res := jsonb_build_object('ok', true, 'action', p_action, 'added_points', v_amount);

        WHEN 'reset_shame_quota' THEN
            -- Mesaj geçmişini veya idempotency kaydını ASLA SİLMEZ;
            -- Ayrı kota tablosunda bugünün used_count değerini 0 yapar ve quota_version'ı artırır.
            INSERT INTO public.shame_message_quotas (user_id, quota_date, used_count, quota_version, updated_at)
            VALUES (p_target_user_id, v_today, 0, 2, NOW())
            ON CONFLICT (user_id, quota_date)
            DO UPDATE SET 
                used_count = 0,
                quota_version = public.shame_message_quotas.quota_version + 1,
                updated_at = NOW();

            v_res := jsonb_build_object('ok', true, 'action', p_action, 'message', 'Hedef kullanıcının utanç mesajı kotası güvenle sıfırlandı.');

        WHEN 'send_alert_notification' THEN
            -- Var olan admin_notifications_log altyapısını kullanır; tek seferlik uyarı iletir.
            v_title := SUBSTRING(COALESCE(NULLIF(TRIM(p_payload->>'title'), ''), '🚨 Yönetici Uyarısı!') FROM 1 FOR 120);
            v_body := COALESCE(NULLIF(TRIM(p_payload->>'body'), ''), 'Dikkat: Yeşil Adım sistem yöneticisinden acil çevre ve aktivite uyarısı.');

            SELECT COALESCE(nickname, 'GM Admin') INTO v_admin_name
            FROM public.users WHERE id = v_admin_id;
            IF v_admin_name IS NULL THEN
                v_admin_name := 'GM Admin';
            END IF;

            INSERT INTO public.admin_notifications_log (
                target_type, target_user_id, title, message_body, severity, sent_by
            ) VALUES (
                'user',
                p_target_user_id,
                v_title,
                v_body,
                'urgent',
                SUBSTRING(v_admin_name FROM 1 FOR 50)
            );

            v_res := jsonb_build_object('ok', true, 'action', p_action, 'message', 'Kullanıcıya rahatsız edici test bildirimi gönderildi.');

        ELSE
            RETURN jsonb_build_object('ok', false, 'message', 'Bilinmeyen GM aksiyonu: ' || p_action);
    END CASE;

    -- 5. Audit Trail Kaydı
    INSERT INTO public.admin_audit_trail (
        admin_user_id, target_user_id, action_type, payload, idempotency_key, result_json
    ) VALUES (
        v_admin_id, p_target_user_id, p_action, p_payload, p_idempotency_key, v_res
    );

    RETURN v_res;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_universal_gm_action FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_universal_gm_action TO authenticated;


-- ============================================================================
-- AŞAMA 2: ROLLBACK İZOLE TEST VE DOĞRULAMALAR
-- ============================================================================

DO $$
DECLARE
    v_admin_id UUID := gen_random_uuid();
    v_target_id UUID := gen_random_uuid();
    v_unauth_id UUID := gen_random_uuid();
    v_res JSONB;
    v_notif_count INT;
    v_audit_count INT;
    v_notif RECORD;
    v_target RECORD;
BEGIN
    -- 1. Fixture Kullanıcıları (Gerçek 01_schema tablosuna uygun)
    INSERT INTO public.users (id, device_id, nickname, gold_coins, today_steps, weekly_points, streak_days, is_demo)
    VALUES 
        (v_admin_id, 'test_pf_admin_' || substr(v_admin_id::text, 1, 8), 'PfAdmin', 100, 0, 0, 0, false),
        (v_target_id, 'test_pf_target_' || substr(v_target_id::text, 1, 8), 'PfTarget', 20, 1000, 10, 0, false),
        (v_unauth_id, 'test_pf_unauth_' || substr(v_unauth_id::text, 1, 8), 'PfUnauth', 10, 0, 0, 0, false);

    -- 2. Yetkisiz Kullanıcı Denetimi
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_unauth_id);
    EXECUTE 'SET LOCAL role = authenticated';

    BEGIN
        v_res := public.rpc_universal_gm_action(
            v_target_id,
            'send_alert_notification',
            jsonb_build_object('title', '🚨 TEST', 'body', 'Yetkisiz deneme'),
            'pf_alert_unauth_01'
        );
        RAISE EXCEPTION 'TEST 1 HATA: server_admins olmayan kullanıcı GM bildirimi gönderebildi!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Yetkisiz erişim: Sunucu yöneticisi%' THEN
            RAISE EXCEPTION 'TEST 1 HATA: Beklenmeyen hata mesajı: %', SQLERRM;
        END IF;
    END;

    -- 3. Yetkili GM Ataması (Gerçek server_admins şeması: user_id, notes)
    RESET ROLE;
    INSERT INTO public.server_admins (user_id, notes)
    VALUES (v_admin_id, 'Preflight Alert Test Admin');

    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_admin_id);
    EXECUTE 'SET LOCAL role = authenticated';

    -- 4. send_alert_notification Pozitif Çağrısı
    v_res := public.rpc_universal_gm_action(
        v_target_id,
        'send_alert_notification',
        jsonb_build_object('title', '🚨 ACİL DURUM UYARISI', 'body', 'Hemen yeşil adıma katılın!'),
        'pf_alert_key_01'
    );

    IF (v_res->>'ok')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 2 HATA: send_alert_notification başarısız: %', v_res;
    END IF;

    -- 5. admin_notifications_log Doğrulaması
    RESET ROLE;
    SELECT * INTO v_notif 
    FROM public.admin_notifications_log 
    WHERE target_user_id = v_target_id AND title = '🚨 ACİL DURUM UYARISI';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'TEST 3 HATA: admin_notifications_log tablosunda bildirim kaydı bulunamadı!';
    END IF;

    IF v_notif.severity != 'urgent' THEN
        RAISE EXCEPTION 'TEST 3 HATA: Bildirim severity urgent değil: %', v_notif.severity;
    END IF;

    IF v_notif.sent_by != 'PfAdmin' THEN
        RAISE EXCEPTION 'TEST 3 HATA: Bildirim gönderen (sent_by) PfAdmin değil: %', v_notif.sent_by;
    END IF;

    -- 6. Idempotency Teyidi (Aynı anahtarla 2. istek tek bildirim bırakmalıdır)
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_admin_id);
    EXECUTE 'SET LOCAL role = authenticated';

    v_res := public.rpc_universal_gm_action(
        v_target_id,
        'send_alert_notification',
        jsonb_build_object('title', '🚨 ACİL DURUM UYARISI', 'body', 'Hemen yeşil adıma katılın!'),
        'pf_alert_key_01'
    );

    IF (v_res->>'duplicate')::BOOLEAN != true THEN
        RAISE EXCEPTION 'TEST 4 HATA: Tekrar istekte duplicate: true dönmedi: %', v_res;
    END IF;

    RESET ROLE;
    SELECT COUNT(*) INTO v_notif_count
    FROM public.admin_notifications_log
    WHERE target_user_id = v_target_id AND title = '🚨 ACİL DURUM UYARISI';

    IF v_notif_count != 1 THEN
        RAISE EXCEPTION 'TEST 4 HATA: Idempotent istekte birden fazla bildirim oluştu! Sayı: %', v_notif_count;
    END IF;

    SELECT COUNT(*) INTO v_audit_count
    FROM public.admin_audit_trail
    WHERE admin_user_id = v_admin_id AND idempotency_key = 'pf_alert_key_01';

    IF v_audit_count != 1 THEN
        RAISE EXCEPTION 'TEST 4 HATA: Idempotent istekte birden fazla audit kaydı oluştu! Sayı: %', v_audit_count;
    END IF;

    -- 7. Sayısal GM Yolları Duman Testi (Mevcut yollar bozulmadı teyidi)
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_admin_id);
    EXECUTE 'SET LOCAL role = authenticated';

    -- 7.1 add_steps (+1500 adım)
    v_res := public.rpc_universal_gm_action(v_target_id, 'add_steps', '{"count": 1500}'::jsonb, 'pf_smoke_steps');
    IF (v_res->>'ok')::BOOLEAN != true THEN RAISE EXCEPTION 'TEST 5.1 HATA: add_steps başarısız: %', v_res; END IF;

    -- 7.2 add_gold (+30 altın)
    v_res := public.rpc_universal_gm_action(v_target_id, 'add_gold', '{"amount": 30}'::jsonb, 'pf_smoke_gold');
    IF (v_res->>'ok')::BOOLEAN != true THEN RAISE EXCEPTION 'TEST 5.2 HATA: add_gold başarısız: %', v_res; END IF;

    -- 7.3 add_streak (+3 gün)
    v_res := public.rpc_universal_gm_action(v_target_id, 'add_streak', '{"days": 3}'::jsonb, 'pf_smoke_streak');
    IF (v_res->>'ok')::BOOLEAN != true THEN RAISE EXCEPTION 'TEST 5.3 HATA: add_streak başarısız: %', v_res; END IF;

    -- 7.4 add_points (+25 puan)
    v_res := public.rpc_universal_gm_action(v_target_id, 'add_points', '{"points": 25}'::jsonb, 'pf_smoke_points');
    IF (v_res->>'ok')::BOOLEAN != true THEN RAISE EXCEPTION 'TEST 5.4 HATA: add_points başarısız: %', v_res; END IF;

    -- 7.5 reset_shame_quota
    v_res := public.rpc_universal_gm_action(v_target_id, 'reset_shame_quota', '{}'::jsonb, 'pf_smoke_quota');
    IF (v_res->>'ok')::BOOLEAN != true THEN RAISE EXCEPTION 'TEST 5.5 HATA: reset_shame_quota başarısız: %', v_res; END IF;

    RESET ROLE;
    SELECT * INTO v_target FROM public.users WHERE id = v_target_id;
    IF v_target.today_steps != 2500 THEN
        RAISE EXCEPTION 'TEST 5.6 HATA: today_steps yanlış (Beklenen 2500, Mevcut: %)', v_target.today_steps;
    END IF;
    IF v_target.gold_coins != 50 THEN
        RAISE EXCEPTION 'TEST 5.7 HATA: gold_coins yanlış (Beklenen 50, Mevcut: %)', v_target.gold_coins;
    END IF;
    IF v_target.streak_days != 3 THEN
        RAISE EXCEPTION 'TEST 5.8 HATA: streak_days yanlış (Beklenen 3, Mevcut: %)', v_target.streak_days;
    END IF;
    IF v_target.weekly_points != 35 THEN
        RAISE EXCEPTION 'TEST 5.9 HATA: weekly_points yanlış (Beklenen 35, Mevcut: %)', v_target.weekly_points;
    END IF;

    RAISE NOTICE 'PREFLIGHT BAŞARILI: Yetkisiz ret, bildirim teslimi, idempotency ve sayısal GM yolları doğrulandı ✅';
END $$;

ROLLBACK; -- Kalıcı test mutasyonu kesinlikle bırakılmaz!
