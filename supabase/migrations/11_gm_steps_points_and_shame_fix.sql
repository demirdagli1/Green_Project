-- ============================================================================
-- Migration 11: GM Adım-Puan Onarımı (Etkinlik Tabanlı Muhasebe) ve Ortak Utanç Panosu
-- ============================================================================
-- 1. v_global_shame_board görünümüne u.is_demo kolonu EN SONA eklenir
--    (CREATE OR REPLACE VIEW mevcut kolon sırasını değiştiremez; yeni kolon yalnız sona eklenebilir).
--    security_invoker = true; anon/authenticated için tüm cihazlarda aynı ortak liste.
-- 2. v_leaderboard_users görünümüne weekly_car_taxi_trips ve weekly_wasted_co2_kg EN SONA eklenir.
-- 3. rpc_universal_gm_action:
--    - set_steps: 0 - 1.000.000 geçerlidir (600.000 dahil).
--    - add_steps: 1 - 100.000 dışı kırpılmadan net ret.
--    - Delta puan = (hedef_adım / 1000) * 5 - bugünkü (İstanbul günü) walk aktivite puanları.
--      Eski GM set_steps aktivite yazmadığı için 600k verilip 0 puan almış kullanıcı,
--      aynı değere set_steps ile +3.000 puan alarak ONARILIR; tekrar çağrı delta 0 verir.
--    - add_steps gün dönümü: today_steps önceki İstanbul gününden kaldıysa taban 0 (çift ödül yok).
-- 4. rpc_record_steps gün sınırı UTC CURRENT_DATE yerine Europe/Istanbul günüdür
--    (GM delta penceresi ve utanç/kota günleriyle aynı gün tanımı).
-- ============================================================================

-- 1. Utanç Panosu Görünümü (Tüm cihazlar için ortak sunucu kaynağı)
CREATE OR REPLACE VIEW public.v_global_shame_board
WITH (security_invoker = true) AS
SELECT
    u.id AS user_id,
    CONCAT(LEFT(u.nickname, 3), '***') AS masked_name,
    u.avatar_url,
    c.name AS clan_name,
    u.weekly_car_taxi_trips,
    u.weekly_car_taxi_km,
    u.weekly_wasted_co2_kg,
    RANK() OVER (ORDER BY u.weekly_wasted_co2_kg DESC, u.weekly_car_taxi_trips DESC) AS global_shame_rank,
    u.is_demo
FROM public.users u
LEFT JOIN public.clans c ON u.clan_id = c.id
WHERE u.weekly_car_taxi_trips > 0;

GRANT SELECT ON public.v_global_shame_board TO anon, authenticated;

-- 2. Liderlik Tablosu Görünümü Güncellemesi (yeni kolonlar sonda)
CREATE OR REPLACE VIEW public.v_leaderboard_users
WITH (security_invoker = true) AS
SELECT
    u.id AS user_id,
    u.nickname,
    u.avatar_url,
    u.frame_slug,
    u.pet_slug,
    u.clan_id,
    c.name AS clan_name,
    c.tag AS clan_tag,
    u.league_tier,
    u.today_steps,
    u.weekly_points,
    u.all_time_points,
    u.weekly_saved_co2_kg,
    u.streak_days,
    u.is_demo,
    u.last_active_at,
    RANK() OVER (ORDER BY u.weekly_points DESC, u.today_steps DESC) AS rank,
    u.weekly_car_taxi_trips,
    u.weekly_wasted_co2_kg
FROM public.users u
LEFT JOIN public.clans c ON u.clan_id = c.id;

GRANT SELECT ON public.v_leaderboard_users TO anon, authenticated;

-- 3. GM Aksiyon RPC Güncellemesi
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

            -- Gün dönümü: today_steps önceki İstanbul gününden kaldıysa taban 0 olur.
            -- (rpc_record_steps ile aynı kural; dünkü adımlara bugün yeniden puan verilmez.)
            IF v_target.last_active_at IS NULL
               OR (v_target.last_active_at AT TIME ZONE 'Europe/Istanbul')::date < v_today THEN
                v_base_steps := 0;
            ELSE
                v_base_steps := v_target.today_steps;
            END IF;
            v_new_steps := v_base_steps + v_amount;

            -- Bugünkü yürüyüş etkinliklerinden kazanılmış puanları hesapla
            SELECT COALESCE(SUM(points_earned), 0) INTO v_already_awarded
            FROM public.activities
            WHERE user_id = p_target_user_id
              AND activity_type = 'walk'
              AND created_at >= v_day_start;

            -- Hedef adıma karşılık gereken puan ile verilmiş puan farkı
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

            -- Bugünkü yürüyüş etkinliklerinden kazanılmış puanları hesapla
            SELECT COALESCE(SUM(points_earned), 0) INTO v_already_awarded
            FROM public.activities
            WHERE user_id = p_target_user_id
              AND activity_type = 'walk'
              AND created_at >= v_day_start;

            -- Delta puan: Beklenen toplam puan ile daha önce verilmiş puan farkı
            -- Bozuk (600k verilip puanı artmamış) kullanıcılar için de tam +3.000 puan onarımı yapar
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


-- 4. Adım Kaydı RPC: Gün sınırı Europe/Istanbul (03'teki sözleşme korunur, yalnız gün tanımı değişir)
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
    v_today DATE := (CURRENT_TIMESTAMP AT TIME ZONE 'Europe/Istanbul')::date;
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

    IF p_step_count IS NULL OR p_step_count <= 0 OR p_step_count > 50000 THEN
        RAISE EXCEPTION 'Geçersiz adım sayısı: %', p_step_count;
    END IF;
    IF p_distance_km IS NULL OR p_distance_km < 0 OR p_distance_km > 100 OR p_distance_km != p_distance_km THEN
        RAISE EXCEPTION 'Geçersiz mesafe miktarı';
    END IF;

    SELECT * INTO v_user FROM public.users WHERE id = v_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kullanıcı bulunamadı';
    END IF;

    -- Gün dönümü (İstanbul): önceki günün adımları sıfırlanır
    IF (v_user.last_active_at AT TIME ZONE 'Europe/Istanbul')::date < v_today THEN
        v_base_steps := 0;
        IF v_user.last_streak_date < v_today - 1 THEN
            v_streak := 0;
        ELSE
            v_streak := v_user.streak_days;
        END IF;
    ELSE
        v_base_steps := v_user.today_steps;
        v_streak := v_user.streak_days;
    END IF;

    v_new_today_steps := v_base_steps + p_step_count;
    -- İstemci puan/CO2 ipuçları yok sayılır; sunucu hesaplar
    v_points_awarded := ((v_new_today_steps / 1000) - (v_base_steps / 1000)) * 5;
    IF v_points_awarded < 0 THEN
        v_points_awarded := 0;
    END IF;
    v_co2_saved := ROUND(GREATEST(p_distance_km, 0) * 0.19, 2);

    IF v_new_today_steps >= 6000 AND (v_user.last_streak_date IS NULL OR v_user.last_streak_date < v_today) THEN
        IF v_user.last_streak_date = v_today - 1 THEN
            v_streak := v_streak + 1;
        ELSE
            v_streak := 1;
        END IF;
        v_last_streak_date := v_today;
    ELSE
        v_last_streak_date := v_user.last_streak_date;
    END IF;

    INSERT INTO public.activities (
        event_id, user_id, activity_type, steps_count,
        distance_km, points_earned, co2_delta_kg,
        verification_status, feedback_message, created_at
    ) VALUES (
        p_event_id, v_user_id, 'walk', p_step_count,
        p_distance_km, v_points_awarded, v_co2_saved,
        'verified', 'Yürüyüş adımları başarıyla kaydedildi.', NOW()
    );

    UPDATE public.users
    SET today_steps = v_new_today_steps,
        weekly_points = weekly_points + v_points_awarded,
        all_time_points = all_time_points + v_points_awarded,
        weekly_saved_co2_kg = weekly_saved_co2_kg + v_co2_saved,
        streak_days = v_streak,
        last_streak_date = v_last_streak_date,
        last_active_at = NOW()
    WHERE id = v_user_id;

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

    INSERT INTO public.processed_events (user_id, event_id, event_type, result_json)
    VALUES (v_user_id, p_event_id, 'step_sync', v_res);

    RETURN v_res;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_record_steps FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_record_steps TO authenticated;
