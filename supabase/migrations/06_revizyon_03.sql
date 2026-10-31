-- ============================================================================
-- 06_revizyon_03.sql
-- Revizyon 03 Güvenli ve Atomik Artımlı Migration (Incremental Safe Migration)
-- Proje: Green_Project (fhaxxraibydsjikxacbb)
-- Root tarafından Supabase Dashboard SQL Editor veya CLI üzerinden uygulanır.
-- ============================================================================

-- 1. Advisor Hatalarını ve search_path Uyarılarını Düzeltme
-- ----------------------------------------------------------------------------
-- compute_league_tier ve trigger fonksiyonlarının search_path'ini sabitle
CREATE OR REPLACE FUNCTION public.compute_league_tier(p_points INT, p_type VARCHAR)
RETURNS INT
LANGUAGE sql
STABLE
SET search_path = 'public', 'pg_temp'
AS $$
    SELECT COALESCE(
        (SELECT tier FROM public.leagues
         WHERE league_type = p_type AND p_points >= min_points
         ORDER BY tier DESC LIMIT 1),
        1
    );
$$;

CREATE OR REPLACE FUNCTION public.trg_sync_user_league_tier()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = 'public', 'pg_temp'
AS $$
BEGIN
    NEW.league_tier := public.compute_league_tier(NEW.weekly_points, 'individual');
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_sync_clan_league_tier()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = 'public', 'pg_temp'
AS $$
BEGIN
    NEW.league_tier := public.compute_league_tier(NEW.weekly_points, 'clan');
    RETURN NEW;
END;
$$;

-- Mevcut Utanç Görünümlerini ALTER VIEW ile yerinde security_invoker = true yap
-- (CREATE OR REPLACE VIEW sütun uyuşmazlığı hatası riskini tamamen engeller)
ALTER VIEW IF EXISTS public.v_clan_shame_board SET (security_invoker = true);
ALTER VIEW IF EXISTS public.v_global_shame_board SET (security_invoker = true);

GRANT SELECT ON public.v_clan_shame_board TO anon, authenticated;
GRANT SELECT ON public.v_global_shame_board TO anon, authenticated;


-- 2. Klan Rol Şeması ve İntra-Clan Hiyerarşi Görünümü
-- ----------------------------------------------------------------------------
ALTER TABLE public.users 
    ADD COLUMN IF NOT EXISTS clan_role VARCHAR(20) NOT NULL DEFAULT 'member'
    CHECK (clan_role IN ('leader', 'elder', 'member'));

-- RLS: clan_role sütun iznini anon ve authenticated rollerine aç
GRANT SELECT (clan_role) ON public.users TO anon, authenticated;

-- Güvenli Klan Üyeleri Görünümü (İntra-Clan Rankings & Hierarchy)
CREATE OR REPLACE VIEW public.v_clan_members
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
    u.clan_role,
    u.weekly_points,
    u.all_time_points,
    u.today_steps,
    u.league_tier,
    u.is_demo,
    u.last_active_at,
    RANK() OVER (PARTITION BY u.clan_id ORDER BY u.weekly_points DESC, u.all_time_points DESC, u.nickname ASC) AS clan_rank
FROM public.users u
JOIN public.clans c ON u.clan_id = c.id;

GRANT SELECT ON public.v_clan_members TO anon, authenticated;


-- 3. Klan Utanç Listesi Görünümü (En Çok İsraf Yapan Klanlar)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_worst_clans
WITH (security_invoker = true) AS
SELECT
    c.id AS clan_id,
    c.name AS clan_name,
    c.tag AS clan_tag,
    c.logo_url,
    c.league_tier,
    c.member_count,
    c.weekly_wasted_co2_kg,
    c.weekly_points,
    c.all_time_points,
    RANK() OVER (ORDER BY c.weekly_wasted_co2_kg DESC, c.weekly_points ASC, c.id ASC) AS rank
FROM public.clans c;

GRANT SELECT ON public.v_worst_clans TO anon, authenticated;


-- 4. Utanç Listesi Dürtme ve Mesajlaşma Tabloları (Ayrı Kota Takibi)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shame_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    target_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    message_text VARCHAR(50) NOT NULL,
    cost_gold INT NOT NULL DEFAULT 10,
    sent_date DATE NOT NULL DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'Europe/Istanbul')::date,
    idempotency_key TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_shame_messages_sender_idempotency UNIQUE (sender_id, idempotency_key)
);

CREATE TABLE IF NOT EXISTS public.shame_message_quotas (
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    quota_date DATE NOT NULL,
    used_count INT NOT NULL DEFAULT 0 CHECK (used_count >= 0),
    quota_version INT NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, quota_date)
);

ALTER TABLE public.shame_messages ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.shame_messages FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.shame_messages TO authenticated;
CREATE POLICY shame_messages_read_own ON public.shame_messages
    FOR SELECT TO authenticated
    USING (auth.uid() = sender_id OR auth.uid() = target_id);

ALTER TABLE public.shame_message_quotas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.shame_message_quotas FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.shame_message_quotas TO authenticated;
CREATE POLICY shame_quotas_read_own ON public.shame_message_quotas
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);


-- 5. Utanç Dürtme RPC (Atomik Kilit + Ayrı Kota Takibi + Doğru Bildirim Kolonları)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_send_shame_message(
    p_target_id UUID,
    p_message TEXT,
    p_idempotency_key TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_sender_id UUID := auth.uid();
    v_sender RECORD;
    v_target RECORD;
    v_clean_msg TEXT;
    v_today DATE := (CURRENT_TIMESTAMP AT TIME ZONE 'Europe/Istanbul')::date;
    v_cached RECORD;
    v_quota RECORD;
    v_sender_gold INT;
BEGIN
    IF v_sender_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim: Oturum bulunamadı';
    END IF;

    IF p_idempotency_key IS NULL OR TRIM(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'Idempotency anahtarı gereklidir';
    END IF;

    IF v_sender_id = p_target_id THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Kendine utanç mesajı gönderemezsin.');
    END IF;

    v_clean_msg := TRIM(COALESCE(p_message, ''));
    IF length(v_clean_msg) < 1 THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Mesaj metni boş olamaz.');
    END IF;
    IF length(v_clean_msg) > 50 THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Mesaj en fazla 50 karakter olabilir.');
    END IF;

    -- 1. Gönderici Seviyesinde Advisory Lock (Yarış durumu engeli)
    PERFORM pg_advisory_xact_lock(hashtext(v_sender_id::text || ':shame_msg:' || p_idempotency_key));

    -- 2. Idempotency Kontrolü (Yalnızca gönderenin kendi anahtarı scope'unda)
    SELECT * INTO v_cached 
    FROM public.shame_messages 
    WHERE sender_id = v_sender_id AND idempotency_key = p_idempotency_key;
    IF FOUND THEN
        RETURN jsonb_build_object(
            'ok', true,
            'duplicate', true,
            'message_id', v_cached.id,
            'message', 'Bu mesaj zaten iletildi (İdempotent yanıt).'
        );
    END IF;

    -- 3. Hedef kullanıcı kontrolü (Yalnızca gerçek kullanıcılar; simülasyon profillerine yalan yok!)
    SELECT * INTO v_target FROM public.users WHERE id = p_target_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Hedef kullanıcı bulunamadı.');
    END IF;
    IF v_target.is_demo THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Hedef kullanıcı simülasyon profilidir. Canlı mesaj gönderilemez.');
    END IF;

    -- 4. Gönderici Satır Kilidi (FOR UPDATE) - Kota kontrolünden ÖNCE kilit alınır!
    SELECT * INTO v_sender FROM public.users WHERE id = v_sender_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Gönderici profili bulunamadı';
    END IF;

    -- 5. Günlük Kota Kontrolü (shame_message_quotas tablosu üzerinden, kilit altında)
    SELECT * INTO v_quota 
    FROM public.shame_message_quotas 
    WHERE user_id = v_sender_id AND quota_date = v_today FOR UPDATE;

    IF FOUND AND v_quota.used_count >= 1 THEN
        RETURN jsonb_build_object(
            'ok', false,
            'message', 'Bugünlük utanç mesajı kotanızı doldurdunuz (Günde en fazla 1 gönderim).'
        );
    END IF;

    -- 6. Bakiye Kontrolü
    IF v_sender.gold_coins < 10 THEN
        RETURN jsonb_build_object(
            'ok', false,
            'message', 'Yetersiz altın! Utanç mesajı göndermek için 10 altın gerekir.'
        );
    END IF;

    -- 7. Bakiye Düşümü
    v_sender_gold := v_sender.gold_coins - 10;
    UPDATE public.users SET gold_coins = v_sender_gold WHERE id = v_sender_id;

    -- 8. Kotayı Artır (Yoksa oluştur)
    INSERT INTO public.shame_message_quotas (user_id, quota_date, used_count, quota_version, updated_at)
    VALUES (v_sender_id, v_today, 1, 1, NOW())
    ON CONFLICT (user_id, quota_date)
    DO UPDATE SET 
        used_count = public.shame_message_quotas.used_count + 1,
        updated_at = NOW();

    -- 9. Mesajı Kaydet (Idempotent geçmiş kalıcıdır, kota sıfırlansa da silinmez)
    INSERT INTO public.shame_messages (
        sender_id, target_id, message_text, cost_gold, sent_date, idempotency_key
    ) VALUES (
        v_sender_id, p_target_id, v_clean_msg, 10, v_today, p_idempotency_key
    );

    -- 10. Hedef Kullanıcıya Bildirim (01_schema.sql kolonları ile %100 birebir uyumlu)
    INSERT INTO public.admin_notifications_log (
        target_type, target_user_id, title, message_body, severity, sent_by
    ) VALUES (
        'user',
        p_target_id,
        'Utanç Tablosu Dürtmesi!',
        COALESCE(v_sender.nickname, 'Bir kullanıcı') || ': "' || v_clean_msg || '"',
        'nudge',
        COALESCE(v_sender.nickname, 'Kullanıcı')
    );

    RETURN jsonb_build_object(
        'ok', true,
        'message', 'Utanç mesajı başarıyla iletildi (10 altın kesildi).',
        'remaining_gold', v_sender_gold
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_send_shame_message FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_send_shame_message TO authenticated;


-- 6. Doğrulanmış Otobüs Yolculuğu ve Ortak Settlement Uzlaştırma RPC
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_record_bus_trip(
    p_event_id TEXT,
    p_distance_km NUMERIC,
    p_bus_score INT DEFAULT 60,
    p_is_short_penalty BOOLEAN DEFAULT false,
    p_confidence NUMERIC DEFAULT 1.0,
    p_stop_code TEXT DEFAULT NULL,
    p_explanation TEXT DEFAULT NULL
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
    v_pts_delta INT := 0;
    v_actual_deducted INT := 0;
    v_co2_saved NUMERIC(8,2) := 0.00;
    v_msg TEXT;
    v_last_scan TIMESTAMPTZ;
    v_last_stop VARCHAR(30);
    v_canonical_stop VARCHAR(30) := COALESCE(NULLIF(TRIM(p_stop_code), ''), 'AUTO_BUS_TRIP');
    v_is_short BOOLEAN;
    v_already_qr_settled BOOLEAN := false;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    IF p_event_id IS NULL OR TRIM(p_event_id) = '' THEN
        RAISE EXCEPTION 'event_id boş olamaz';
    END IF;

    -- 1. Sayısal Aralık ve NaN Koruması (Postgres finite numeric doğrulaması)
    IF p_distance_km IS NULL 
       OR p_distance_km = 'NaN'::numeric 
       OR NOT (p_distance_km > 0.0 AND p_distance_km <= 200.0) THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Geçersiz mesafe ölçümü (0 - 200 km aralığında olmalıdır).');
    END IF;

    IF p_bus_score IS NULL OR p_bus_score < 0 OR p_bus_score > 100 THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Geçersiz otobüs olasılık skoru (0 - 100 arası).');
    END IF;

    IF p_confidence IS NULL 
       OR p_confidence = 'NaN'::numeric 
       OR NOT (p_confidence >= 0.0 AND p_confidence <= 1.0) THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Geçersiz sensör güven katsayısı.');
    END IF;

    -- Güven Eşiği Kontrolü: Güven < 0.60 veya skor < 60 ise otomatik ödül/ceza verilmez
    IF p_confidence < 0.60 OR p_bus_score < 60 THEN
        RETURN jsonb_build_object(
            'ok', false,
            'message', 'Yetersiz sensör güveni veya otobüs olasılık skoru (<60); otomatik işlem yapılmadı.'
        );
    END IF;

    -- 2. Advisory Lock (Yarış durumu engeli)
    PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || ':bus_trip:' || p_event_id));

    -- 3. Idempotency Kontrolü
    SELECT * INTO v_cached FROM public.processed_events WHERE user_id = v_user_id AND event_id = p_event_id;
    IF FOUND THEN
        RETURN v_cached.result_json || jsonb_build_object('duplicate', true);
    END IF;

    -- 4. KULLANICI SATIR KİLİDİ (FOR UPDATE) - Tüm transit kontrollerinden ÖNCE kilitlenir!
    SELECT * INTO v_user FROM public.users WHERE id = v_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kullanıcı bulunamadı';
    END IF;

    -- 5. Ortak Yolculuk (Joint Transit Settlement) Kontrolü:
    -- Son 45 dk içinde herhangi bir transit kaydı (QR, NFC veya önceki biniş) var mı?
    SELECT last_scanned_at, stop_code INTO v_last_scan, v_last_stop
    FROM public.transit_cooldowns
    WHERE user_id = v_user_id
      AND last_scanned_at >= NOW() - INTERVAL '45 minutes'
    ORDER BY last_scanned_at DESC
    LIMIT 1;

    IF v_last_scan IS NOT NULL THEN
        v_already_qr_settled := true;
    END IF;

    -- 6. Kısa Otobüs Kuralı: Server Mesafesi Kesin Karar Vericidir!
    -- p_is_short_penalty tek başına uzun mesafeyi kısa sayamaz. Mesafe <= 0.50 km olmalıdır.
    v_is_short := (p_distance_km <= 0.50);

    IF v_is_short THEN
        -- KISA OTOBÜS YOLCULUĞU (≤ 500m):
        -- Şartname gereği net sonuç -3 puan olmalıdır.
        IF v_already_qr_settled THEN
            -- Yolcu biniş anında QR okutup +3 puan almıştı. Şimdi yolculuk <=500m bitti.
            -- Net sonucun -3 olması için: +3 geri alınır (-3) ve ilave ceza (-3) verilir = -6 puan!
            v_actual_deducted := LEAST(v_user.weekly_points, 6);
            v_pts_delta := -v_actual_deducted;
            v_co2_saved := 0.00;
            v_msg := COALESCE(p_explanation, 'Kısa otobüs yolculuğu (≤500m): Başlangıçtaki QR ödülü (+3) iptal edildi ve -3 ceza kesildi (Net -' || v_actual_deducted || ' puan).');
        ELSE
            -- QR okutulmamıştı, saf otomatik tespit: 3 puan düşülür.
            v_actual_deducted := LEAST(v_user.weekly_points, 3);
            v_pts_delta := -v_actual_deducted;
            v_co2_saved := 0.00;
            IF v_actual_deducted > 0 THEN
                v_msg := COALESCE(p_explanation, 'Kısa otobüs yolculuğu (≤500m): Dingil gibi yürümek yerine otobüse bindin! -' || v_actual_deducted || ' puan ceza kesildi.');
            ELSE
                v_msg := COALESCE(p_explanation, 'Kısa otobüs yolculuğu (≤500m): Puanınız zaten 0 olduğu için ilave puan düşülemedi.');
            END IF;
        END IF;

        UPDATE public.users
        SET weekly_points = weekly_points - v_actual_deducted,
            last_active_at = NOW()
        WHERE id = v_user_id;

        IF v_user.clan_id IS NOT NULL AND v_actual_deducted > 0 THEN
            UPDATE public.clans
            SET weekly_points = GREATEST(0, weekly_points - v_actual_deducted)
            WHERE id = v_user.clan_id;
        END IF;

    ELSE
        -- STANDART OTOBÜS YOLCULUĞU (> 500m):
        v_co2_saved := ROUND(p_distance_km * (0.192 - 0.035), 2);

        IF v_already_qr_settled THEN
            -- Kullanıcı binişte QR ile zaten +3 puan aldı; mükerrer puan verilmez (Tek yolculuk tek ödül)
            v_pts_delta := 0;
            v_msg := COALESCE(p_explanation, 'Otobüs yolculuğu tamamlandı (' || p_distance_km || ' km). Binişte QR ile puan alındığı için ilave puan verilmedi, ' || v_co2_saved || ' kg CO₂ tasarrufu işlendi.');

            UPDATE public.users
            SET weekly_saved_co2_kg = weekly_saved_co2_kg + v_co2_saved,
                last_active_at = NOW()
            WHERE id = v_user_id;

            IF v_user.clan_id IS NOT NULL THEN
                UPDATE public.clans
                SET weekly_saved_co2_kg = weekly_saved_co2_kg + v_co2_saved
                WHERE id = v_user.clan_id;
            END IF;
        ELSE
            -- Binişte QR okutulmamış, otomatik doğrulama ile +3 puan verilir
            v_pts_delta := 3;
            v_msg := COALESCE(p_explanation, 'Otobüs / Dolmuş yolculuğu otomatik doğrulandı! (+3 Puan, ' || v_co2_saved || ' kg CO₂ tasarrufu)');

            UPDATE public.users
            SET weekly_points = weekly_points + v_pts_delta,
                all_time_points = all_time_points + v_pts_delta,
                weekly_saved_co2_kg = weekly_saved_co2_kg + v_co2_saved,
                last_active_at = NOW()
            WHERE id = v_user_id;

            IF v_user.clan_id IS NOT NULL THEN
                UPDATE public.clans
                SET weekly_points = weekly_points + v_pts_delta,
                    all_time_points = all_time_points + v_pts_delta,
                    weekly_saved_co2_kg = weekly_saved_co2_kg + v_co2_saved
                WHERE id = v_user.clan_id;
            END IF;
        END IF;
    END IF;

    -- 7. Cooldown Tablosunu Güncelle (Sonraki 45 dk için mükerrer işlemleri önler)
    INSERT INTO public.transit_cooldowns (user_id, stop_code, last_scanned_at)
    VALUES (v_user_id, v_canonical_stop, NOW())
    ON CONFLICT (user_id, stop_code)
    DO UPDATE SET last_scanned_at = NOW();

    -- 8. Aktiviteyi Kaydet (01_schema.sql CHECK kısıtları ile %100 uyumlu)
    INSERT INTO public.activities (
        event_id, user_id, activity_type, distance_km,
        points_earned, co2_delta_kg, verification_status, feedback_message
    ) VALUES (
        p_event_id, v_user_id, 'public_transit', p_distance_km,
        v_pts_delta, v_co2_saved, 'verified', v_msg
    );

    -- 9. İdempotent Olay Kaydı (event_type NOT NULL kısıtı ile tam uyumlu)
    INSERT INTO public.processed_events (user_id, event_id, event_type, result_json)
    VALUES (v_user_id, p_event_id, 'bus_trip', jsonb_build_object(
        'ok', true,
        'points_delta', v_pts_delta,
        'co2_saved_kg', v_co2_saved,
        'is_short_penalty', v_is_short,
        'already_qr_settled', v_already_qr_settled,
        'message', v_msg
    ));

    RETURN jsonb_build_object(
        'ok', true,
        'points_delta', v_pts_delta,
        'co2_saved_kg', v_co2_saved,
        'is_short_penalty', v_is_short,
        'already_qr_settled', v_already_qr_settled,
        'message', v_msg
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_record_bus_trip FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_record_bus_trip TO authenticated;


-- 7. Evrensel GM Paneli RPC ve Audit Trail
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.admin_audit_trail (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_user_id UUID NOT NULL,
    target_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    action_type TEXT NOT NULL,
    payload JSONB NOT NULL,
    idempotency_key TEXT NOT NULL,
    result_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_admin_audit_admin_idempotency UNIQUE (admin_user_id, idempotency_key)
);

ALTER TABLE public.admin_audit_trail ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.admin_audit_trail FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.admin_audit_trail TO authenticated;
CREATE POLICY admin_audit_trail_admin_only ON public.admin_audit_trail
    FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.server_admins WHERE user_id = auth.uid()));

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
            UPDATE public.users SET today_steps = today_steps + v_amount WHERE id = p_target_user_id;
            v_res := jsonb_build_object('ok', true, 'action', p_action, 'added', v_amount);

        WHEN 'set_steps' THEN
            v_amount := (p_payload->>'total')::INT;
            IF v_amount IS NULL OR v_amount < 0 OR v_amount > 1000000 THEN
                RETURN jsonb_build_object('ok', false, 'message', 'Toplam adım 0 ile 1.000.000 arasında olmalıdır.');
            END IF;
            UPDATE public.users SET today_steps = v_amount WHERE id = p_target_user_id;
            v_res := jsonb_build_object('ok', true, 'action', p_action, 'new_total', v_amount);

        WHEN 'add_streak' THEN
            v_amount := (p_payload->>'days')::INT;
            IF v_amount IS NULL OR v_amount < 1 OR v_amount > 365 THEN
                RETURN jsonb_build_object('ok', false, 'message', 'Seri gün sayısı 1 ile 365 arasında olmalıdır.');
            END IF;
            UPDATE public.users SET streak_days = streak_days + v_amount WHERE id = p_target_user_id;
            v_res := jsonb_build_object('ok', true, 'action', p_action, 'added_days', v_amount);

        WHEN 'set_streak' THEN
            v_amount := (p_payload->>'days')::INT;
            IF v_amount IS NULL OR v_amount < 0 OR v_amount > 365 THEN
                RETURN jsonb_build_object('ok', false, 'message', 'Seri gün sayısı 0 ile 365 arasında olmalıdır.');
            END IF;
            UPDATE public.users SET streak_days = v_amount WHERE id = p_target_user_id;
            v_res := jsonb_build_object('ok', true, 'action', p_action, 'new_days', v_amount);

        WHEN 'add_gold' THEN
            v_amount := (p_payload->>'amount')::INT;
            IF v_amount IS NULL OR v_amount < -100000 OR v_amount > 100000 THEN
                RETURN jsonb_build_object('ok', false, 'message', 'Altın miktarı -100.000 ile +100.000 arasında olmalıdır.');
            END IF;
            IF v_target.gold_coins + v_amount < 0 THEN
                RETURN jsonb_build_object('ok', false, 'message', 'Kullanıcının altını negatif olamaz.');
            END IF;
            UPDATE public.users SET gold_coins = gold_coins + v_amount WHERE id = p_target_user_id;
            v_res := jsonb_build_object('ok', true, 'action', p_action, 'added_gold', v_amount);

        WHEN 'set_gold' THEN
            v_amount := (p_payload->>'total')::INT;
            IF v_amount IS NULL OR v_amount < 0 OR v_amount > 1000000 THEN
                RETURN jsonb_build_object('ok', false, 'message', 'Toplam altın 0 ile 1.000.000 arasında olmalıdır.');
            END IF;
            UPDATE public.users SET gold_coins = v_amount WHERE id = p_target_user_id;
            v_res := jsonb_build_object('ok', true, 'action', p_action, 'new_gold', v_amount);

        WHEN 'add_points' THEN
            v_amount := (p_payload->>'points')::INT;
            IF v_amount IS NULL OR v_amount < -10000 OR v_amount > 10000 THEN
                RETURN jsonb_build_object('ok', false, 'message', 'Puan miktarı -10.000 ile +10.000 arasında olmalıdır.');
            END IF;
            UPDATE public.users 
            SET weekly_points = GREATEST(0, weekly_points + v_amount),
                all_time_points = GREATEST(0, all_time_points + v_amount)
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
