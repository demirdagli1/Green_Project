-- ============================================================================
-- preflight_gm_steps_and_shame_fix.sql — Migration 11 Preflight
-- AÇIK BEGIN ... ROLLBACK: canlı veriyi değiştirmez. Root tek seferde çalıştırır.
-- AŞAMA 1, supabase/migrations/11_gm_steps_points_and_shame_fix.sql ile BİREBİR aynıdır.
-- Kapsam: kolon sırası, yetkisiz ret, 600k set (+3000, klan/haftalık/tüm zamanlar),
-- bozuk 600k aynı değer onarımı + idempotency + tekrar ödül 0, add/set limit net ret,
-- gün dönümü çift ödül yok, rpc_record_steps İstanbul günü, ortak utanç snapshot'ı,
-- gerçek/demo/kendine mesaj hedefi ve kota.
-- ============================================================================

BEGIN;

-- ============================================================================
-- AŞAMA 1: MIGRATION 11 (birebir)
-- ============================================================================
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

-- ============================================================================
-- AŞAMA 2: ROLLBACK İZOLE TESTLER (hiçbir kalıcı mutasyon bırakmaz)
-- ============================================================================
DO $$
DECLARE
    v_admin_id   UUID := gen_random_uuid();
    v_fresh_id   UUID := gen_random_uuid();
    v_broken_id  UUID := gen_random_uuid();
    v_stale_id   UUID := gen_random_uuid();
    v_walker_id  UUID := gen_random_uuid();
    v_sender_id  UUID := gen_random_uuid();
    v_real_id    UUID := gen_random_uuid();
    v_demo_id    UUID := gen_random_uuid();
    v_day_start  TIMESTAMPTZ := ((CURRENT_TIMESTAMP AT TIME ZONE 'Europe/Istanbul')::date)::timestamp AT TIME ZONE 'Europe/Istanbul';
    v_clan_id INT;
    v_res JSONB;
    v_u RECORD;
    v_c RECORD;
    v_cnt INT;
    v_pos INT;
    v_snap_a TEXT;
    v_snap_b TEXT;
    v_snap_anon TEXT;
BEGIN
    -- 0. Kolon sırası: yeni kolonlar sonda olmalı (CREATE OR REPLACE VIEW kuralı)
    SELECT ordinal_position INTO v_pos FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'v_global_shame_board' AND column_name = 'global_shame_rank';
    IF v_pos != 8 THEN RAISE EXCEPTION 'TEST 0 HATA: global_shame_rank sırası değişti: %', v_pos; END IF;
    SELECT ordinal_position INTO v_pos FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'v_global_shame_board' AND column_name = 'is_demo';
    IF v_pos != 9 THEN RAISE EXCEPTION 'TEST 0 HATA: is_demo sonda değil: %', v_pos; END IF;
    SELECT ordinal_position INTO v_pos FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'v_leaderboard_users' AND column_name = 'rank';
    IF v_pos != 17 THEN RAISE EXCEPTION 'TEST 0 HATA: leaderboard rank sırası değişti: %', v_pos; END IF;

    -- 1. Fixture
    INSERT INTO public.clans (name, tag) VALUES ('PF11 Klan ' || substr(v_admin_id::text, 1, 8), 'PF11')
    RETURNING id INTO v_clan_id;

    INSERT INTO public.users (id, device_id, nickname, gold_coins, today_steps, weekly_points, all_time_points,
                              clan_id, is_demo, last_active_at, weekly_car_taxi_trips, weekly_wasted_co2_kg)
    VALUES
        (v_admin_id,  'pf11_adm_' || substr(v_admin_id::text, 1, 8),  'PfAdmin',  100, 0,      0,  0,  NULL,      false, NOW(), 0, 0),
        (v_fresh_id,  'pf11_frs_' || substr(v_fresh_id::text, 1, 8),  'PfFresh',  100, 0,      0,  0,  v_clan_id, false, NOW(), 0, 0),
        (v_broken_id, 'pf11_brk_' || substr(v_broken_id::text, 1, 8), 'PfBroken', 100, 600000, 0,  0,  v_clan_id, false, NOW(), 0, 0),
        (v_stale_id,  'pf11_stl_' || substr(v_stale_id::text, 1, 8),  'PfStale',  100, 10000,  50, 50, NULL,      false, NOW() - INTERVAL '2 days', 0, 0),
        (v_walker_id, 'pf11_wlk_' || substr(v_walker_id::text, 1, 8), 'PfWalker', 100, 5000,   25, 25, NULL,      false, v_day_start - INTERVAL '1 hour', 0, 0),
        (v_sender_id, 'pf11_snd_' || substr(v_sender_id::text, 1, 8), 'PfSender', 100, 0,      0,  0,  NULL,      false, NOW(), 0, 0),
        (v_real_id,   'pf11_rel_' || substr(v_real_id::text, 1, 8),   'PfRealCar', 100, 0,     0,  0,  NULL,      false, NOW(), 2, 5.00),
        (v_demo_id,   'pf11_dmo_' || substr(v_demo_id::text, 1, 8),   'PfDemoCar', 100, 0,     0,  0,  NULL,      true,  NOW(), 3, 9.00);

    INSERT INTO public.server_admins (user_id, notes) VALUES (v_admin_id, 'preflight 11');

    -- 2. Yetkisiz ret
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_sender_id);
    EXECUTE 'SET LOCAL role = authenticated';
    BEGIN
        v_res := public.rpc_universal_gm_action(v_fresh_id, 'set_steps', '{"total": 600000}'::jsonb, 'pf11_unauth');
        RAISE EXCEPTION 'TEST 1 HATA: yetkisiz GM aksiyonu çalıştı';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Yetkisiz erişim: Sunucu yöneticisi%' THEN
            RAISE EXCEPTION 'TEST 1 HATA: beklenmeyen hata: %', SQLERRM;
        END IF;
    END;
    RESET ROLE;

    -- 3. Gerçek 600k set: +3000 kullanıcı/haftalık/tüm zamanlar/klan
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_admin_id);
    EXECUTE 'SET LOCAL role = authenticated';
    v_res := public.rpc_universal_gm_action(v_fresh_id, 'set_steps', '{"total": 600000}'::jsonb, 'pf11_set_fresh');
    RESET ROLE;
    IF (v_res->>'ok')::boolean IS DISTINCT FROM true OR (v_res->>'points_delta')::int != 3000 THEN
        RAISE EXCEPTION 'TEST 2 HATA: 600k set: %', v_res;
    END IF;
    SELECT * INTO v_u FROM public.users WHERE id = v_fresh_id;
    IF v_u.today_steps != 600000 OR v_u.weekly_points != 3000 OR v_u.all_time_points != 3000 THEN
        RAISE EXCEPTION 'TEST 2 HATA: steps=% weekly=% alltime=%', v_u.today_steps, v_u.weekly_points, v_u.all_time_points;
    END IF;
    SELECT * INTO v_c FROM public.clans WHERE id = v_clan_id;
    IF v_c.weekly_points != 3000 OR v_c.all_time_points != 3000 THEN
        RAISE EXCEPTION 'TEST 2 HATA: klan weekly=% alltime=%', v_c.weekly_points, v_c.all_time_points;
    END IF;

    -- 4. Bozuk 600k (adım var, puan 0) aynı değer onarımı; aynı anahtar duplicate; farklı anahtar delta 0
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_admin_id);
    EXECUTE 'SET LOCAL role = authenticated';
    v_res := public.rpc_universal_gm_action(v_broken_id, 'set_steps', '{"total": 600000}'::jsonb, 'pf11_repair');
    IF (v_res->>'points_delta')::int != 3000 THEN RAISE EXCEPTION 'TEST 3 HATA: onarım: %', v_res; END IF;
    v_res := public.rpc_universal_gm_action(v_broken_id, 'set_steps', '{"total": 600000}'::jsonb, 'pf11_repair');
    IF (v_res->>'duplicate')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST 3 HATA: idempotency: %', v_res; END IF;
    v_res := public.rpc_universal_gm_action(v_broken_id, 'set_steps', '{"total": 600000}'::jsonb, 'pf11_repair_again');
    IF (v_res->>'points_delta')::int != 0 THEN RAISE EXCEPTION 'TEST 3 HATA: tekrar ödül: %', v_res; END IF;
    RESET ROLE;
    SELECT * INTO v_u FROM public.users WHERE id = v_broken_id;
    IF v_u.weekly_points != 3000 OR v_u.all_time_points != 3000 THEN
        RAISE EXCEPTION 'TEST 3 HATA: onarım sonrası weekly=% alltime=%', v_u.weekly_points, v_u.all_time_points;
    END IF;
    SELECT COUNT(*) INTO v_cnt FROM public.activities WHERE user_id = v_broken_id AND activity_type = 'walk';
    IF v_cnt != 1 THEN RAISE EXCEPTION 'TEST 3 HATA: walk aktivite sayısı %', v_cnt; END IF;
    SELECT * INTO v_c FROM public.clans WHERE id = v_clan_id;
    IF v_c.weekly_points != 6000 THEN RAISE EXCEPTION 'TEST 3 HATA: klan=%', v_c.weekly_points; END IF;

    -- 5. add_steps limitleri: kırpmadan net ret, mutasyon/audit yok
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_admin_id);
    EXECUTE 'SET LOCAL role = authenticated';
    v_res := public.rpc_universal_gm_action(v_fresh_id, 'add_steps', '{"count": 100001}'::jsonb, 'pf11_add_over');
    IF (v_res->>'ok')::boolean IS DISTINCT FROM false OR (v_res->>'message') NOT LIKE '%1 ile 100.000 arasında%' THEN
        RAISE EXCEPTION 'TEST 4 HATA: 100001 reddedilmedi: %', v_res;
    END IF;
    v_res := public.rpc_universal_gm_action(v_fresh_id, 'add_steps', '{"count": 0}'::jsonb, 'pf11_add_zero');
    IF (v_res->>'ok')::boolean IS DISTINCT FROM false THEN RAISE EXCEPTION 'TEST 4 HATA: 0 reddedilmedi: %', v_res; END IF;
    v_res := public.rpc_universal_gm_action(v_fresh_id, 'set_steps', '{"total": 1000001}'::jsonb, 'pf11_set_over');
    IF (v_res->>'ok')::boolean IS DISTINCT FROM false THEN RAISE EXCEPTION 'TEST 4 HATA: set 1000001 reddedilmedi: %', v_res; END IF;
    RESET ROLE;
    SELECT * INTO v_u FROM public.users WHERE id = v_fresh_id;
    IF v_u.today_steps != 600000 OR v_u.weekly_points != 3000 THEN
        RAISE EXCEPTION 'TEST 4 HATA: ret sonrası mutasyon steps=% pts=%', v_u.today_steps, v_u.weekly_points;
    END IF;
    SELECT COUNT(*) INTO v_cnt FROM public.admin_audit_trail
    WHERE admin_user_id = v_admin_id AND idempotency_key IN ('pf11_add_over', 'pf11_add_zero', 'pf11_set_over');
    IF v_cnt != 0 THEN RAISE EXCEPTION 'TEST 4 HATA: ret audit yazdı: %', v_cnt; END IF;

    -- 6. Aynı gün add_steps: 600k + 5000 -> +25
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_admin_id);
    EXECUTE 'SET LOCAL role = authenticated';
    v_res := public.rpc_universal_gm_action(v_fresh_id, 'add_steps', '{"count": 5000}'::jsonb, 'pf11_add_5k');
    RESET ROLE;
    SELECT * INTO v_u FROM public.users WHERE id = v_fresh_id;
    IF v_u.today_steps != 605000 OR v_u.weekly_points != 3025 THEN
        RAISE EXCEPTION 'TEST 5 HATA: steps=% pts=%', v_u.today_steps, v_u.weekly_points;
    END IF;

    -- 7. Gün dönümü: dünden kalan 10000 adıma bugün yeniden puan verilmez (+5, +55 değil)
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_admin_id);
    EXECUTE 'SET LOCAL role = authenticated';
    v_res := public.rpc_universal_gm_action(v_stale_id, 'add_steps', '{"count": 1000}'::jsonb, 'pf11_add_stale');
    RESET ROLE;
    SELECT * INTO v_u FROM public.users WHERE id = v_stale_id;
    IF v_u.today_steps != 1000 OR v_u.weekly_points != 55 OR (v_res->>'points_delta')::int != 5 THEN
        RAISE EXCEPTION 'TEST 6 HATA: gün dönümü çift ödül: steps=% pts=% res=%', v_u.today_steps, v_u.weekly_points, v_res;
    END IF;

    -- 8. rpc_record_steps İstanbul günü: dün 23:00 (İstanbul) son aktif -> sıfırlanır; GM set aynı değer delta 0
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_walker_id);
    EXECUTE 'SET LOCAL role = authenticated';
    v_res := public.rpc_record_steps('pf11_walk_1', 1000, 0.70);
    IF (v_res->>'points_awarded')::int != 5 THEN RAISE EXCEPTION 'TEST 7 HATA: record_steps: %', v_res; END IF;
    v_res := public.rpc_record_steps('pf11_walk_1', 1000, 0.70);
    IF (v_res->>'duplicate')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST 7 HATA: record dup: %', v_res; END IF;
    RESET ROLE;
    SELECT * INTO v_u FROM public.users WHERE id = v_walker_id;
    IF v_u.today_steps != 1000 OR v_u.weekly_points != 30 THEN
        RAISE EXCEPTION 'TEST 7 HATA: İstanbul gün sıfırlaması: steps=% pts=%', v_u.today_steps, v_u.weekly_points;
    END IF;
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_admin_id);
    EXECUTE 'SET LOCAL role = authenticated';
    v_res := public.rpc_universal_gm_action(v_walker_id, 'set_steps', '{"total": 1000}'::jsonb, 'pf11_walker_set');
    RESET ROLE;
    IF (v_res->>'points_delta')::int != 0 THEN RAISE EXCEPTION 'TEST 7 HATA: GM/record tutarsız: %', v_res; END IF;

    -- 9. Ortak utanç snapshot'ı: iki farklı kullanıcı + anon aynı listeyi görür
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_sender_id);
    EXECUTE 'SET LOCAL role = authenticated';
    SELECT string_agg(user_id::text || ':' || global_shame_rank || ':' || is_demo, ',' ORDER BY global_shame_rank, user_id)
      INTO v_snap_a FROM public.v_global_shame_board;
    RESET ROLE;
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_real_id);
    EXECUTE 'SET LOCAL role = authenticated';
    SELECT string_agg(user_id::text || ':' || global_shame_rank || ':' || is_demo, ',' ORDER BY global_shame_rank, user_id)
      INTO v_snap_b FROM public.v_global_shame_board;
    RESET ROLE;
    EXECUTE 'SET LOCAL request.jwt.claim.sub = '''';';
    EXECUTE 'SET LOCAL role = anon';
    SELECT string_agg(user_id::text || ':' || global_shame_rank || ':' || is_demo, ',' ORDER BY global_shame_rank, user_id)
      INTO v_snap_anon FROM public.v_global_shame_board;
    RESET ROLE;
    IF v_snap_a IS DISTINCT FROM v_snap_b OR v_snap_a IS DISTINCT FROM v_snap_anon THEN
        RAISE EXCEPTION 'TEST 8 HATA: utanç snapshot cihaz/kullanıcıya göre farklı';
    END IF;
    IF position(v_real_id::text || ':' IN v_snap_a) = 0 OR position(v_demo_id::text || ':' IN v_snap_a) = 0 THEN
        RAISE EXCEPTION 'TEST 8 HATA: fixture kullanıcıları snapshot''ta yok';
    END IF;
    SELECT COUNT(*) INTO v_cnt FROM public.v_global_shame_board
    WHERE (user_id = v_demo_id AND is_demo) OR (user_id = v_real_id AND NOT is_demo);
    IF v_cnt != 2 THEN RAISE EXCEPTION 'TEST 8 HATA: demo/gerçek bayrağı yanlış'; END IF;

    -- 10. Mesaj hedefi: kendine ret, demo ret (altın korunur), gerçek hedef kabul (hedef user_id korunur), kota
    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_sender_id);
    EXECUTE 'SET LOCAL role = authenticated';
    v_res := public.rpc_send_shame_message(v_sender_id, 'Kendime', 'pf11_msg_self');
    IF (v_res->>'ok')::boolean IS DISTINCT FROM false THEN RAISE EXCEPTION 'TEST 9 HATA: kendine mesaj: %', v_res; END IF;
    v_res := public.rpc_send_shame_message(v_demo_id, 'Demo hedef', 'pf11_msg_demo');
    IF (v_res->>'ok')::boolean IS DISTINCT FROM false OR (v_res->>'message') NOT LIKE '%simülasyon%' THEN
        RAISE EXCEPTION 'TEST 9 HATA: demo hedef: %', v_res;
    END IF;
    RESET ROLE;
    SELECT * INTO v_u FROM public.users WHERE id = v_sender_id;
    IF v_u.gold_coins != 100 THEN RAISE EXCEPTION 'TEST 9 HATA: ret sonrası altın kesildi: %', v_u.gold_coins; END IF;

    EXECUTE format('SET LOCAL request.jwt.claim.sub = %L', v_sender_id);
    EXECUTE 'SET LOCAL role = authenticated';
    v_res := public.rpc_send_shame_message(v_real_id, 'Arabayı bırak!', 'pf11_msg_real');
    IF (v_res->>'ok')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST 9 HATA: gerçek hedef: %', v_res; END IF;
    v_res := public.rpc_send_shame_message(v_real_id, 'İkinci mesaj', 'pf11_msg_real_2');
    IF (v_res->>'ok')::boolean IS DISTINCT FROM false THEN RAISE EXCEPTION 'TEST 9 HATA: günlük kota aşıldı: %', v_res; END IF;
    RESET ROLE;
    SELECT COUNT(*) INTO v_cnt FROM public.shame_messages WHERE sender_id = v_sender_id AND target_id = v_real_id;
    IF v_cnt != 1 THEN RAISE EXCEPTION 'TEST 9 HATA: mesaj kaydı sayısı %', v_cnt; END IF;
    SELECT COUNT(*) INTO v_cnt FROM public.admin_notifications_log WHERE target_user_id = v_real_id;
    IF v_cnt < 1 THEN RAISE EXCEPTION 'TEST 9 HATA: hedefe bildirim yazılmadı'; END IF;
    SELECT * INTO v_u FROM public.users WHERE id = v_sender_id;
    IF v_u.gold_coins != 90 THEN RAISE EXCEPTION 'TEST 9 HATA: altın %', v_u.gold_coins; END IF;

    RAISE NOTICE 'PREFLIGHT MIGRATION 11: TÜM TESTLER PASS (ROLLBACK ile geri alınacak)';
END;
$$;

ROLLBACK;
