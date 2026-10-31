-- ============================================================================
-- preflight_gm_vehicle_penalty.sql
-- Yeşil Adım — Evrensel GM Utanç Tablosu Araç Cezası Preflight Doğrulama Testi
--
-- Güvenli deneme: Tamamı tek bir açık transaction içinde çalışır ve sonda
-- ROLLBACK edilir. Canlı veritabanında kalıcı hiçbir değişiklik bırakmaz.
--
-- Doğrulanan Senaryolar:
-- 1. Yetkisiz ret: server_admins üyesi olmayan kullanıcı add_vehicle_penalty çağıramaz.
-- 2. GM araç cezası ekleme: Hedef kullanıcının weekly_car_taxi_trips (+1), weekly_car_taxi_km (+10km),
--    weekly_wasted_co2_kg (+1.92kg) atomik artırılır; klan CO2 israfı güncellenir.
-- 3. Utanç görünümü: Hedef kullanıcı derhal v_global_shame_board içinde görünür ve sıralama alır.
-- 4. Envanter/Puan/Altın bütünlüğü: Puan ve altın kesintisi yapılmaz, envanter korunur.
-- 5. İdempotency & Mükerrer engeli: Aynı idempotency_key ile tekrar çağrıldığında
--    duplicate=true döner; haftalık trip veya CO2 ikinci kez ASLA artmaz.
-- 6. Sayısal sınır kontrolleri: 0 km ve 600 km reddedilir (0.1 - 500 km aralığı zorunlu).
-- 7. Cihazlar/oturumlar arası ortak okuma: Anonim ve farklı iki oturum v_global_shame_board
--    üzerinde hedef kullanıcıyı birebir aynı sıra ve değerlerle görür.
-- ============================================================================

BEGIN;

-- 1. Migration 12 Gövdesini Uygula (Canlıya aktarılacak aynı kod)
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
    v_new_steps INT;
    v_already_awarded INT := 0;
    v_points_delta INT := 0;
    v_streak INT;
    v_res JSONB;
    v_cached RECORD;
    v_today DATE := (CURRENT_TIMESTAMP AT TIME ZONE 'Europe/Istanbul')::date;
    v_day_start TIMESTAMPTZ := ((CURRENT_TIMESTAMP AT TIME ZONE 'Europe/Istanbul')::date)::timestamp AT TIME ZONE 'Europe/Istanbul';
    v_base_steps INT;
    v_title VARCHAR(120);
    v_body TEXT;
    v_admin_name VARCHAR(50);
    v_distance_km NUMERIC(8,2);
    v_wasted_co2 NUMERIC(8,2);
BEGIN
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim: Giriş yapmadınız';
    END IF;

    -- server_admins kontrolü
    IF NOT EXISTS (SELECT 1 FROM public.server_admins WHERE user_id = v_admin_id) THEN
        RAISE EXCEPTION 'Yetkisiz erişim: Sunucu yöneticisi (server_admins) değilsiniz!';
    END IF;

    IF p_idempotency_key IS NULL OR TRIM(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'Idempotency anahtarı gereklidir';
    END IF;

    -- 1. Advisory Lock
    PERFORM pg_advisory_xact_lock(hashtext(v_admin_id::text || ':gm:' || p_idempotency_key));

    -- 2. Idempotency Kontrolü
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

            IF v_target.last_active_at IS NULL
               OR (v_target.last_active_at AT TIME ZONE 'Europe/Istanbul')::date < v_today THEN
                v_base_steps := 0;
            ELSE
                v_base_steps := v_target.today_steps;
            END IF;
            v_new_steps := v_base_steps + v_amount;

            SELECT COALESCE(SUM(points_earned), 0) INTO v_already_awarded
            FROM public.activities
            WHERE user_id = p_target_user_id
              AND activity_type = 'walk'
              AND created_at >= v_day_start;

            v_points_delta := ((v_new_steps / 1000) * 5) - v_already_awarded;

            UPDATE public.users 
            SET today_steps = v_new_steps,
                weekly_points = GREATEST(0, weekly_points + v_points_delta),
                all_time_points = GREATEST(0, all_time_points + v_points_delta),
                last_active_at = NOW()
            WHERE id = p_target_user_id;

            IF v_target.clan_id IS NOT NULL AND v_points_delta != 0 THEN
                UPDATE public.clans 
                SET weekly_points = GREATEST(0, weekly_points + v_points_delta),
                    all_time_points = GREATEST(0, all_time_points + v_points_delta)
                WHERE id = v_target.clan_id;
            END IF;

            IF v_points_delta != 0 THEN
                INSERT INTO public.activities (
                    event_id, user_id, activity_type, steps_count,
                    distance_km, points_earned, co2_delta_kg,
                    verification_status, feedback_message, created_at
                ) VALUES (
                    'gm_add_' || p_idempotency_key,
                    p_target_user_id,
                    'walk',
                    v_amount,
                    ROUND((v_amount * 0.00075)::numeric, 2),
                    v_points_delta,
                    0.00,
                    'verified',
                    'GM add_steps adım ve puan senkronizasyonu',
                    NOW()
                );
            END IF;

            IF v_new_steps >= 6000 AND (v_target.last_streak_date IS NULL OR v_target.last_streak_date < v_today) THEN
                IF v_target.last_streak_date = v_today - INTERVAL '1 day' THEN
                    v_streak := v_target.streak_days + 1;
                ELSE
                    v_streak := 1;
                END IF;
                UPDATE public.users SET streak_days = v_streak, last_streak_date = v_today WHERE id = p_target_user_id;
            END IF;

            v_res := jsonb_build_object(
                'ok', true,
                'action', p_action,
                'added', v_amount,
                'new_total', v_new_steps,
                'points_delta', v_points_delta
            );

        WHEN 'set_steps' THEN
            v_amount := (p_payload->>'total')::INT;
            IF v_amount IS NULL OR v_amount < 0 OR v_amount > 1000000 THEN
                RETURN jsonb_build_object('ok', false, 'message', 'Toplam adım 0 ile 1.000.000 arasında olmalıdır.');
            END IF;

            v_new_steps := v_amount;

            SELECT COALESCE(SUM(points_earned), 0) INTO v_already_awarded
            FROM public.activities
            WHERE user_id = p_target_user_id
              AND activity_type = 'walk'
              AND created_at >= v_day_start;

            v_points_delta := ((v_new_steps / 1000) * 5) - v_already_awarded;

            UPDATE public.users 
            SET today_steps = v_new_steps,
                weekly_points = GREATEST(0, weekly_points + v_points_delta),
                all_time_points = GREATEST(0, all_time_points + v_points_delta),
                last_active_at = NOW()
            WHERE id = p_target_user_id;

            IF v_target.clan_id IS NOT NULL AND v_points_delta != 0 THEN
                UPDATE public.clans 
                SET weekly_points = GREATEST(0, weekly_points + v_points_delta),
                    all_time_points = GREATEST(0, all_time_points + v_points_delta)
                WHERE id = v_target.clan_id;
            END IF;

            IF v_points_delta != 0 THEN
                INSERT INTO public.activities (
                    event_id, user_id, activity_type, steps_count,
                    distance_km, points_earned, co2_delta_kg,
                    verification_status, feedback_message, created_at
                ) VALUES (
                    'gm_set_' || p_idempotency_key,
                    p_target_user_id,
                    'walk',
                    v_amount,
                    ROUND((v_amount * 0.00075)::numeric, 2),
                    v_points_delta,
                    0.00,
                    'verified',
                    'GM set_steps adım ve puan senkronizasyonu',
                    NOW()
                );
            END IF;

            IF v_new_steps >= 6000 AND (v_target.last_streak_date IS NULL OR v_target.last_streak_date < v_today) THEN
                IF v_target.last_streak_date = v_today - INTERVAL '1 day' THEN
                    v_streak := v_target.streak_days + 1;
                ELSE
                    v_streak := 1;
                END IF;
                UPDATE public.users SET streak_days = v_streak, last_streak_date = v_today WHERE id = p_target_user_id;
            END IF;

            v_res := jsonb_build_object(
                'ok', true,
                'action', p_action,
                'new_total', v_new_steps,
                'points_delta', v_points_delta
            );

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
            INSERT INTO public.shame_message_quotas (user_id, quota_date, used_count, quota_version, updated_at)
            VALUES (p_target_user_id, v_today, 0, 2, NOW())
            ON CONFLICT (user_id, quota_date)
            DO UPDATE SET 
                used_count = 0,
                quota_version = public.shame_message_quotas.quota_version + 1,
                updated_at = NOW();

            v_res := jsonb_build_object('ok', true, 'action', p_action, 'message', 'Hedef kullanıcının utanç mesajı kotası güvenle sıfırlandı.');

        WHEN 'send_alert_notification' THEN
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

        WHEN 'add_vehicle_penalty', 'record_vehicle_penalty' THEN
            v_distance_km := COALESCE(NULLIF((p_payload->>'distance_km'), '')::NUMERIC, 8.50);
            IF v_distance_km IS NULL OR v_distance_km < 0.1 OR v_distance_km > 500 OR v_distance_km != v_distance_km THEN
                RETURN jsonb_build_object('ok', false, 'message', 'Mesafe 0.1 ile 500 km arasında olmalıdır.');
            END IF;

            -- Harcanan CO2: Mesafe × 0.192 kg/km (en az 0.01 kg)
            v_wasted_co2 := GREATEST(0.01, ROUND((v_distance_km * 0.192)::numeric, 2));

            -- Kullanıcı araç ve utanç sayaçlarını atomik artır (Puan, altın ve envanter kesinlikle korunur)
            UPDATE public.users 
            SET weekly_car_taxi_trips = weekly_car_taxi_trips + 1,
                weekly_car_taxi_km = weekly_car_taxi_km + v_distance_km,
                weekly_wasted_co2_kg = weekly_wasted_co2_kg + v_wasted_co2,
                last_active_at = NOW()
            WHERE id = p_target_user_id;

            -- Klan israf sayacını artır
            IF v_target.clan_id IS NOT NULL THEN
                UPDATE public.clans 
                SET weekly_wasted_co2_kg = weekly_wasted_co2_kg + v_wasted_co2
                WHERE id = v_target.clan_id;
            END IF;

            -- Utanç aktivitesi kaydı ekle
            INSERT INTO public.activities (
                event_id, user_id, activity_type, distance_km,
                avg_speed_kmh, points_earned, co2_delta_kg,
                verification_status, feedback_message, created_at
            ) VALUES (
                'gm_veh_' || p_idempotency_key,
                p_target_user_id,
                'car_taxi_penalty',
                v_distance_km,
                68.0,
                0,
                -v_wasted_co2,
                'shame_logged',
                'GM yetkili utanç kaydı ve CO₂ israfı işlendi',
                NOW()
            );

            v_res := jsonb_build_object(
                'ok', true,
                'action', p_action,
                'trips_added', 1,
                'distance_km', v_distance_km,
                'wasted_co2_kg', v_wasted_co2,
                'message', 'Hedef kullanıcıya araba/taksi utanç kaydı başarıyla eklendi.'
            );

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

-- 2. Test Yürütme Bloğu
DO $$
DECLARE
    v_admin_id   UUID := gen_random_uuid();
    v_unauth_id  UUID := gen_random_uuid();
    v_target_id  UUID := gen_random_uuid();
    v_viewer_b   UUID := gen_random_uuid();
    v_clan_id    INT;
    v_res        JSONB;
    v_u          RECORD;
    v_c          RECORD;
    v_cnt        INT;
    v_rank       INT;
    v_shame_user UUID;
    v_snap_a     TEXT;
    v_snap_b     TEXT;
    v_snap_anon  TEXT;
BEGIN
    -- Fixture Oluştur
    INSERT INTO public.clans (name, tag) VALUES ('PF12 Klan ' || substr(v_admin_id::text, 1, 8), 'PF12')
    RETURNING id INTO v_clan_id;

    INSERT INTO public.users (id, device_id, nickname, gold_coins, today_steps, weekly_points, all_time_points,
                              clan_id, is_demo, last_active_at, weekly_car_taxi_trips, weekly_wasted_co2_kg)
    VALUES
        (v_admin_id,  'pf12_adm_' || substr(v_admin_id::text, 1, 8),  'Pf12Admin',  200, 5000, 25, 25, NULL,      false, NOW(), 0, 0.00),
        (v_unauth_id, 'pf12_una_' || substr(v_unauth_id::text, 1, 8), 'Pf12Unauth', 100, 1000, 5,  5,  NULL,      false, NOW(), 0, 0.00),
        (v_target_id, 'pf12_tgt_' || substr(v_target_id::text, 1, 8), 'Pf12Target', 500, 8000, 40, 40, v_clan_id, false, NOW(), 0, 0.00),
        (v_viewer_b,  'pf12_viw_' || substr(v_viewer_b::text, 1, 8),  'Pf12Viewer', 100, 2000, 10, 10, NULL,      false, NOW(), 0, 0.00);

    INSERT INTO public.server_admins (user_id, notes) VALUES (v_admin_id, 'preflight 12 admin');

    -- TEST 1: Yetkisiz çağrı reddi (server_admins üyesi olmayan kullanıcı)
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_unauth_id);
    EXECUTE 'SET LOCAL role = authenticated';
    BEGIN
        v_res := public.rpc_universal_gm_action(v_target_id, 'add_vehicle_penalty', '{"distance_km": 10.0}'::jsonb, 'pf12_unauth_key');
        RAISE EXCEPTION 'TEST 1 HATA: Yetkisiz kullanıcı GM aksiyonunu çalıştırabildi!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Yetkisiz erişim: Sunucu yöneticisi%' THEN
            RAISE EXCEPTION 'TEST 1 HATA: Beklenmeyen hata mesajı: %', SQLERRM;
        END IF;
    END;
    RESET ROLE;

    -- TEST 2: Yetkili GM araba/taksi cezası ekleme
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_admin_id);
    EXECUTE 'SET LOCAL role = authenticated';
    v_res := public.rpc_universal_gm_action(v_target_id, 'add_vehicle_penalty', '{"distance_km": 10.0}'::jsonb, 'pf12_veh_key_1');
    RESET ROLE;

    IF (v_res->>'ok')::boolean IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'TEST 2 HATA: add_vehicle_penalty başarısız: %', v_res;
    END IF;
    IF (v_res->>'trips_added')::int != 1 OR (v_res->>'wasted_co2_kg')::numeric != 1.92 THEN
        RAISE EXCEPTION 'TEST 2 HATA: Yanıt alanları hatalı: %', v_res;
    END IF;

    -- Kullanıcı sayaçları ve puan/altın bütünlüğü
    SELECT * INTO v_u FROM public.users WHERE id = v_target_id;
    IF v_u.weekly_car_taxi_trips != 1 THEN
        RAISE EXCEPTION 'TEST 2 HATA: weekly_car_taxi_trips beklenen 1, gerçek: %', v_u.weekly_car_taxi_trips;
    END IF;
    IF v_u.weekly_wasted_co2_kg != 1.92 THEN
        RAISE EXCEPTION 'TEST 2 HATA: weekly_wasted_co2_kg beklenen 1.92, gerçek: %', v_u.weekly_wasted_co2_kg;
    END IF;
    IF v_u.weekly_car_taxi_km != 10.00 THEN
        RAISE EXCEPTION 'TEST 2 HATA: weekly_car_taxi_km beklenen 10.00, gerçek: %', v_u.weekly_car_taxi_km;
    END IF;
    -- Puan ve altın korunmalı:
    IF v_u.weekly_points != 40 OR v_u.all_time_points != 40 OR v_u.gold_coins != 500 THEN
        RAISE EXCEPTION 'TEST 2 HATA: Puan veya altın bozuldu! points=%, gold=%', v_u.weekly_points, v_u.gold_coins;
    END IF;

    -- Klan CO2 sayacı
    SELECT * INTO v_c FROM public.clans WHERE id = v_clan_id;
    IF v_c.weekly_wasted_co2_kg != 1.92 THEN
        RAISE EXCEPTION 'TEST 2 HATA: Klan weekly_wasted_co2_kg beklenen 1.92, gerçek: %', v_c.weekly_wasted_co2_kg;
    END IF;

    -- Aktivite kaydı doğrulaması
    SELECT COUNT(*) INTO v_cnt FROM public.activities
    WHERE user_id = v_target_id AND activity_type = 'car_taxi_penalty' AND points_earned = 0 AND co2_delta_kg = -1.92;
    IF v_cnt != 1 THEN
        RAISE EXCEPTION 'TEST 2 HATA: activities utanç kaydı oluşturulmadı!';
    END IF;

    -- TEST 3: v_global_shame_board içinde görünme
    SELECT user_id, global_shame_rank INTO v_shame_user, v_rank
    FROM public.v_global_shame_board
    WHERE user_id = v_target_id;
    IF v_shame_user IS NULL OR v_rank IS NULL THEN
        RAISE EXCEPTION 'TEST 3 HATA: Hedef kullanıcı v_global_shame_board içinde görünmüyor!';
    END IF;

    -- TEST 4: İdempotency & Tekrar çağrıda mükerrer ceza oluşmaması
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_admin_id);
    EXECUTE 'SET LOCAL role = authenticated';
    v_res := public.rpc_universal_gm_action(v_target_id, 'add_vehicle_penalty', '{"distance_km": 10.0}'::jsonb, 'pf12_veh_key_1');
    RESET ROLE;

    IF (v_res->>'duplicate')::boolean IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'TEST 4 HATA: Tekrar eden çağrıda duplicate bayrağı dönmedi: %', v_res;
    END IF;

    SELECT * INTO v_u FROM public.users WHERE id = v_target_id;
    IF v_u.weekly_car_taxi_trips != 1 OR v_u.weekly_wasted_co2_kg != 1.92 THEN
        RAISE EXCEPTION 'TEST 4 HATA: Tekrarlanan istekte çifte ceza kesildi! trips=%, wasted=%', v_u.weekly_car_taxi_trips, v_u.weekly_wasted_co2_kg;
    END IF;

    -- TEST 5: Sayısal sınır kontrolleri
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_admin_id);
    EXECUTE 'SET LOCAL role = authenticated';
    v_res := public.rpc_universal_gm_action(v_target_id, 'add_vehicle_penalty', '{"distance_km": 0.0}'::jsonb, 'pf12_veh_zero');
    IF (v_res->>'ok')::boolean IS NOT FALSE THEN
        RAISE EXCEPTION 'TEST 5 HATA: 0 km mesafe kabul edildi: %', v_res;
    END IF;

    v_res := public.rpc_universal_gm_action(v_target_id, 'add_vehicle_penalty', '{"distance_km": 600.0}'::jsonb, 'pf12_veh_over');
    IF (v_res->>'ok')::boolean IS NOT FALSE THEN
        RAISE EXCEPTION 'TEST 5 HATA: 600 km mesafe kabul edildi: %', v_res;
    END IF;
    RESET ROLE;

    -- TEST 6: İki oturum ve anonim için v_global_shame_board ortak okuma
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_target_id);
    EXECUTE 'SET LOCAL role = authenticated';
    SELECT string_agg(user_id::text || ':' || weekly_car_taxi_trips::text || ':' || weekly_wasted_co2_kg::text, ',' ORDER BY global_shame_rank, user_id)
      INTO v_snap_a FROM public.v_global_shame_board;
    RESET ROLE;

    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_viewer_b);
    EXECUTE 'SET LOCAL role = authenticated';
    SELECT string_agg(user_id::text || ':' || weekly_car_taxi_trips::text || ':' || weekly_wasted_co2_kg::text, ',' ORDER BY global_shame_rank, user_id)
      INTO v_snap_b FROM public.v_global_shame_board;
    RESET ROLE;

    EXECUTE 'SET LOCAL role = anon';
    SELECT string_agg(user_id::text || ':' || weekly_car_taxi_trips::text || ':' || weekly_wasted_co2_kg::text, ',' ORDER BY global_shame_rank, user_id)
      INTO v_snap_anon FROM public.v_global_shame_board;
    RESET ROLE;

    IF v_snap_a IS DISTINCT FROM v_snap_b OR v_snap_a IS DISTINCT FROM v_snap_anon THEN
        RAISE EXCEPTION 'TEST 6 HATA: v_global_shame_board farklı oturumlarda eşleşmiyor! a=%, b=%, anon=%', v_snap_a, v_snap_b, v_snap_anon;
    END IF;

    RAISE NOTICE '>>> PREFLIGHT MIGRATION 12 BAŞARIYLA TAMAMLANDI: TÜM TESTLER GEÇTİ (%%100 PASS) <<<';
END $$;

ROLLBACK;
