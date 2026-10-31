-- ============================================================================
-- 12_gm_vehicle_penalty.sql
-- Yeşil Adım — Evrensel GM Utanç Tablosu Araç/Taksi Cezası Ekleme (Revizyon 12)
--
-- Kapsam:
-- 1. rpc_universal_gm_action fonksiyonuna 'add_vehicle_penalty' / 'record_vehicle_penalty'
--    aksiyonu eklenir.
-- 2. Yalnızca server_admins tablosunda kayıtlı yöneticiler tarafından çalıştırılabilir.
-- 3. Sayısal mesafe doğrulaması (0.1 - 500 km), CO2 israf hesabı (0.192 kg/km).
-- 4. Hedef kullanıcının weekly_car_taxi_trips ve weekly_wasted_co2_kg değerlerini artırır;
--    kullanıcı doğrudan v_global_shame_board görünümünde listelenir.
-- 5. Klan üyesi ise klanın weekly_wasted_co2_kg değeri güncellenir.
-- 6. Puan, altın ve envanter kesinlikle korunur (puan/altın kesintisi yapılmaz).
-- 7. activities tablosuna 'car_taxi_penalty' aktivite kaydı ve admin_audit_trail tablosuna
--    idempotency anahtarlı denetim kaydı işlenir (çift çağrıda mükerrer ceza oluşmaz).
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

GRANT EXECUTE ON FUNCTION public.rpc_universal_gm_action TO authenticated;
