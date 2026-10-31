-- ============================================================================
-- 01_schema.sql
-- Yeşil Adım Supabase Şeması: Tablolar, Kısıtlar, İndeksler ve Güvenli Görünümler
-- Proje: Green_Project (fhaxxraibydsjikxacbb)
-- ============================================================================

-- 1. Lig Tanımları Tablosu
CREATE TABLE IF NOT EXISTS public.leagues (
    id SERIAL PRIMARY KEY,
    league_type VARCHAR(20) NOT NULL CHECK (league_type IN ('individual', 'clan')),
    tier INT NOT NULL CHECK (tier BETWEEN 1 AND 6),
    name VARCHAR(50) NOT NULL,
    min_points INT NOT NULL CHECK (min_points >= 0),
    badge_slug VARCHAR(50) NOT NULL,
    color_hex VARCHAR(10) NOT NULL,
    description TEXT,
    CONSTRAINT uq_leagues_type_tier UNIQUE (league_type, tier)
);

-- 2. Klanlar Tablosu
CREATE TABLE IF NOT EXISTS public.clans (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    tag VARCHAR(15) NOT NULL,
    logo_url VARCHAR(255),
    league_tier INT NOT NULL DEFAULT 1 CHECK (league_tier BETWEEN 1 AND 6),
    weekly_points INT NOT NULL DEFAULT 0 CHECK (weekly_points >= 0),
    all_time_points INT NOT NULL DEFAULT 0 CHECK (all_time_points >= 0),
    weekly_saved_co2_kg NUMERIC(8,2) NOT NULL DEFAULT 0.00 CHECK (weekly_saved_co2_kg >= 0),
    weekly_wasted_co2_kg NUMERIC(8,2) NOT NULL DEFAULT 0.00 CHECK (weekly_wasted_co2_kg >= 0),
    member_count INT NOT NULL DEFAULT 0 CHECK (member_count >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Kullanıcılar Tablosu (Sessiz Anon Auth / auth.uid() Sahipliği)
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT auth.uid(),
    device_id VARCHAR(100) NOT NULL UNIQUE,
    nickname VARCHAR(50) NOT NULL,
    avatar_url VARCHAR(255) NOT NULL DEFAULT 'assets/avatars/user_sen.png',
    frame_slug VARCHAR(50) NOT NULL DEFAULT 'none',
    pet_slug VARCHAR(50) DEFAULT 'none',
    clan_id INT REFERENCES public.clans(id) ON DELETE SET NULL,
    league_tier INT NOT NULL DEFAULT 1 CHECK (league_tier BETWEEN 1 AND 6),
    today_steps INT NOT NULL DEFAULT 0 CHECK (today_steps >= 0),
    weekly_points INT NOT NULL DEFAULT 0 CHECK (weekly_points >= 0),
    all_time_points INT NOT NULL DEFAULT 0 CHECK (all_time_points >= 0),
    gold_coins INT NOT NULL DEFAULT 100 CHECK (gold_coins >= 0),
    streak_days INT NOT NULL DEFAULT 0 CHECK (streak_days >= 0),
    last_streak_date DATE,
    weekly_saved_co2_kg NUMERIC(8,2) NOT NULL DEFAULT 0.00 CHECK (weekly_saved_co2_kg >= 0),
    weekly_wasted_co2_kg NUMERIC(8,2) NOT NULL DEFAULT 0.00 CHECK (weekly_wasted_co2_kg >= 0),
    weekly_car_taxi_trips INT NOT NULL DEFAULT 0 CHECK (weekly_car_taxi_trips >= 0),
    weekly_car_taxi_km NUMERIC(8,2) NOT NULL DEFAULT 0.00 CHECK (weekly_car_taxi_km >= 0),
    bio VARCHAR(300) NOT NULL DEFAULT '',
    photo_path TEXT,
    is_demo BOOLEAN NOT NULL DEFAULT FALSE,
    last_active_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. Toplu Taşıma Durakları (NFC / QR)
CREATE TABLE IF NOT EXISTS public.transit_stops (
    id SERIAL PRIMARY KEY,
    stop_code VARCHAR(30) NOT NULL UNIQUE,
    nfc_uid VARCHAR(50) NOT NULL UNIQUE,
    qr_payload VARCHAR(100) NOT NULL UNIQUE,
    route_name VARCHAR(100) NOT NULL,
    stop_name VARCHAR(100) NOT NULL,
    latitude NUMERIC(9,6) NOT NULL,
    longitude NUMERIC(9,6) NOT NULL,
    avg_trip_km NUMERIC(5,2) NOT NULL DEFAULT 6.50,
    points_reward INT NOT NULL DEFAULT 3 CHECK (points_reward >= 0),
    co2_saved_per_trip_kg NUMERIC(5,2) NOT NULL DEFAULT 1.15 CHECK (co2_saved_per_trip_kg >= 0)
);

-- 5. Mağaza Kozmetikleri
CREATE TABLE IF NOT EXISTS public.shop_items (
    id SERIAL PRIMARY KEY,
    item_slug VARCHAR(50) NOT NULL UNIQUE,
    category VARCHAR(20) NOT NULL CHECK (category IN ('avatar', 'frame', 'pet', 'title')),
    name VARCHAR(80) NOT NULL,
    price_gold INT NOT NULL CHECK (price_gold >= 0),
    asset_preview VARCHAR(255) NOT NULL,
    description TEXT
);

-- 6. Kullanıcı Envanteri (Satın Alınan Kozmetikler)
CREATE TABLE IF NOT EXISTS public.user_inventory (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    item_slug VARCHAR(50) NOT NULL REFERENCES public.shop_items(item_slug) ON DELETE CASCADE,
    purchased_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_user_inventory_item UNIQUE (user_id, item_slug)
);

-- 7. İdempotent Olay Kayıt Tablosu (Offline Yeniden Gönderim Çift İşlem Engeli)
CREATE TABLE IF NOT EXISTS public.processed_events (
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    event_id VARCHAR(100) NOT NULL,
    event_type VARCHAR(40) NOT NULL,
    result_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, event_id)
);

-- 8. Durak Tarama Cooldown Takip Tablosu
CREATE TABLE IF NOT EXISTS public.transit_cooldowns (
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    stop_code VARCHAR(30) NOT NULL,
    last_scanned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, stop_code)
);

-- 9. Aktivite Hareket Logları Tablosu
CREATE TABLE IF NOT EXISTS public.activities (
    id SERIAL PRIMARY KEY,
    event_id VARCHAR(100),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    activity_type VARCHAR(25) NOT NULL CHECK (activity_type IN ('walk', 'bike', 'public_transit', 'car_taxi_penalty')),
    steps_count INT DEFAULT 0 CHECK (steps_count >= 0),
    distance_km NUMERIC(6,2) DEFAULT 0.00,
    avg_speed_kmh NUMERIC(5,2) DEFAULT 0.00,
    max_speed_kmh NUMERIC(5,2) DEFAULT 0.00,
    accel_variance NUMERIC(5,3) DEFAULT 0.000,
    transit_stop_id INT REFERENCES public.transit_stops(id) ON DELETE SET NULL,
    points_earned INT NOT NULL DEFAULT 0,
    co2_delta_kg NUMERIC(6,2) NOT NULL DEFAULT 0.00,
    verification_status VARCHAR(30) NOT NULL DEFAULT 'verified' CHECK (verification_status IN ('verified', 'rejected_speed_spoof', 'rejected_duplicate_qr', 'shame_logged')),
    feedback_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 10. Bildirim Şablonları
CREATE TABLE IF NOT EXISTS public.notification_templates (
    id SERIAL PRIMARY KEY,
    trigger_code VARCHAR(40) NOT NULL UNIQUE,
    title VARCHAR(100) NOT NULL,
    body_template TEXT NOT NULL,
    action_button_text VARCHAR(50) NOT NULL,
    severity VARCHAR(20) NOT NULL DEFAULT 'savage'
);

-- 11. Admin ve Sistem Canlı Bildirim Kuyruğu (Realtime)
CREATE TABLE IF NOT EXISTS public.admin_notifications_log (
    id SERIAL PRIMARY KEY,
    target_type VARCHAR(20) NOT NULL CHECK (target_type IN ('user', 'clan', 'all')),
    target_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    target_clan_id INT REFERENCES public.clans(id) ON DELETE CASCADE,
    template_code VARCHAR(40),
    title VARCHAR(120) NOT NULL,
    message_body TEXT NOT NULL,
    severity VARCHAR(20) DEFAULT 'savage' CHECK (severity IN ('nudge', 'savage', 'urgent', 'critical', 'reward')),
    is_delivered BOOLEAN DEFAULT FALSE,
    sent_by VARCHAR(50) DEFAULT 'Hackathon_Admin',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 12. Haftalık Şampiyonlar Tablosu (week_id UNIQUE ile Idempotent Sıfırlama)
CREATE TABLE IF NOT EXISTS public.weekly_champions (
    id SERIAL PRIMARY KEY,
    week_id VARCHAR(20) UNIQUE,
    week_label VARCHAR(50) NOT NULL,
    champion_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    champion_user_points INT NOT NULL,
    champion_clan_id INT REFERENCES public.clans(id) ON DELETE SET NULL,
    champion_clan_points INT NOT NULL,
    total_community_saved_co2_kg NUMERIC(10,2) NOT NULL,
    announced_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 13. Sunucu Yöneticileri Tablosu (Güvenli Sunucu İçi Admin Yetkilendirmesi)
CREATE TABLE IF NOT EXISTS public.server_admins (
    user_id UUID PRIMARY KEY,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- İNDEKSLER (Performans ve RLS Filtreleme Hızı İçin)
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_users_clan_id ON public.users(clan_id);
CREATE INDEX IF NOT EXISTS idx_users_weekly_points ON public.users(weekly_points DESC);
CREATE INDEX IF NOT EXISTS idx_users_is_demo ON public.users(is_demo);
CREATE INDEX IF NOT EXISTS idx_users_device_id ON public.users(device_id);
CREATE INDEX IF NOT EXISTS idx_clans_weekly_points ON public.clans(weekly_points DESC);
CREATE INDEX IF NOT EXISTS idx_user_inventory_user_id ON public.user_inventory(user_id);
CREATE INDEX IF NOT EXISTS idx_activities_user_id ON public.activities(user_id);
CREATE INDEX IF NOT EXISTS idx_activities_transit_stop_id ON public.activities(transit_stop_id);
CREATE INDEX IF NOT EXISTS idx_activities_created_at ON public.activities(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_notifications_target_user ON public.admin_notifications_log(target_user_id);
CREATE INDEX IF NOT EXISTS idx_admin_notifications_target_clan ON public.admin_notifications_log(target_clan_id);
CREATE INDEX IF NOT EXISTS idx_processed_events_created_at ON public.processed_events(created_at);

-- ============================================================================
-- GÜVENLİ GÖRÜNÜMLER (VIEWS) - (security_invoker = true)
-- device_id veya oturum verisi kamuya açık sıralamalara sızmaz
-- ============================================================================

-- Bireysel Genel Lider Tablosu (device_id hariç, güvenli genel alanlar)
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
    RANK() OVER (ORDER BY u.weekly_points DESC, u.today_steps DESC) AS rank
FROM public.users u
LEFT JOIN public.clans c ON u.clan_id = c.id;

-- Klan Genel Lider Tablosu
CREATE OR REPLACE VIEW public.v_clan_leaderboard
WITH (security_invoker = true) AS
SELECT
    c.id AS clan_id,
    c.name AS clan_name,
    c.tag AS clan_tag,
    c.logo_url,
    c.league_tier,
    c.weekly_points,
    c.all_time_points,
    c.weekly_saved_co2_kg,
    c.weekly_wasted_co2_kg,
    c.member_count,
    RANK() OVER (ORDER BY c.weekly_points DESC, c.all_time_points DESC) AS rank
FROM public.clans c;

-- Klan İçi Utanç Tablosu (İsimler maskeli: "Ahmet" -> "Ahm***", güvenli definer projeksiyon)
CREATE OR REPLACE VIEW public.v_clan_shame_board AS
SELECT
    u.clan_id,
    c.name AS clan_name,
    u.id AS user_id,
    CONCAT(LEFT(u.nickname, 3), '***') AS masked_name,
    u.avatar_url,
    u.weekly_car_taxi_trips,
    u.weekly_car_taxi_km,
    u.weekly_wasted_co2_kg,
    RANK() OVER (PARTITION BY u.clan_id ORDER BY u.weekly_wasted_co2_kg DESC, u.weekly_car_taxi_trips DESC) AS shame_rank
FROM public.users u
JOIN public.clans c ON u.clan_id = c.id
WHERE u.weekly_car_taxi_trips > 0;

-- Genel Utanç Tablosu (İsimler maskeli: "Ahmet" -> "Ahm***", güvenli definer projeksiyon)
CREATE OR REPLACE VIEW public.v_global_shame_board AS
SELECT
    u.id AS user_id,
    CONCAT(LEFT(u.nickname, 3), '***') AS masked_name,
    u.avatar_url,
    c.name AS clan_name,
    u.weekly_car_taxi_trips,
    u.weekly_car_taxi_km,
    u.weekly_wasted_co2_kg,
    RANK() OVER (ORDER BY u.weekly_wasted_co2_kg DESC, u.weekly_car_taxi_trips DESC) AS global_shame_rank
FROM public.users u
LEFT JOIN public.clans c ON u.clan_id = c.id
WHERE u.weekly_car_taxi_trips > 0;



-- ============================================================================
-- 02_security_rls.sql
-- Satır Düzeyinde Güvenlik (RLS), Sahiplik Kısıtları ve Sütun Yetkilendirmeleri
-- Proje: Green_Project (fhaxxraibydsjikxacbb)
-- ============================================================================

-- 1. Tüm tablolarda RLS Zorunlu Kılınması
ALTER TABLE public.leagues ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transit_stops ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.processed_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transit_cooldowns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_notifications_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weekly_champions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.server_admins ENABLE ROW LEVEL SECURITY;

-- 2. Varsayılan Yetkileri Sıfırlama (En Az Yetki İlkesi / Least Privilege)
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM authenticated;

-- 3. Kamusal Referans Tabloları İzinleri ve Politikaları
-- Ligler: Statik oyun kademeleri, herkes okuyabilir
GRANT SELECT ON public.leagues TO anon, authenticated;
CREATE POLICY leagues_select_all ON public.leagues
    FOR SELECT TO anon, authenticated
    USING (true);

-- Toplu Taşıma Durakları: Yalnızca genel durak bilgileri; nfc_uid ve qr_payload donanım sırları gizlidir!
GRANT SELECT (
    id, stop_code, route_name, stop_name, latitude, longitude,
    avg_trip_km, points_reward, co2_saved_per_trip_kg
) ON public.transit_stops TO anon, authenticated;
CREATE POLICY transit_stops_select_all ON public.transit_stops
    FOR SELECT TO anon, authenticated
    USING (true);

-- Mağaza Ürünleri: Herkes okuyabilir
GRANT SELECT ON public.shop_items TO anon, authenticated;
CREATE POLICY shop_items_select_all ON public.shop_items
    FOR SELECT TO anon, authenticated
    USING (true);

-- Haftalık Şampiyonlar: Herkes okuyabilir
GRANT SELECT ON public.weekly_champions TO anon, authenticated;
CREATE POLICY weekly_champions_select_all ON public.weekly_champions
    FOR SELECT TO anon, authenticated
    USING (true);

-- Klanlar: Herkes okuyabilir
GRANT SELECT ON public.clans TO anon, authenticated;
CREATE POLICY clans_select_all ON public.clans
    FOR SELECT TO anon, authenticated
    USING (true);

-- Bildirim Şablonları: Kamusal ve normal kullanıcılara kapalı; sadece sunucu adminleri görebilir
GRANT SELECT ON public.notification_templates TO authenticated;
CREATE POLICY notification_templates_admin_only ON public.notification_templates
    FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.server_admins WHERE user_id = (select auth.uid())));

-- 4. Kullanıcı Tablosu (Users) Güvenliği
-- Sütun Seviyesi Kısıtlama:
-- device_id, gold_coins, last_streak_date, weekly_wasted_co2_kg, weekly_car_taxi_trips, weekly_car_taxi_km KAMUYA KAPALIDIR.
-- Kullanıcı doğrudan 'SELECT * FROM users' veya 'SELECT gold_coins FROM users' çağıramaz (insufficient_privilege).
-- Altın ve donanım kimliği yalnızca oturum sahibinin rpc_get_my_profile() çağrısıyla okunabilir.
GRANT SELECT (
    id, nickname, avatar_url, frame_slug, pet_slug, clan_id,
    league_tier, today_steps, weekly_points, all_time_points,
    weekly_saved_co2_kg, streak_days,
    bio, photo_path, is_demo, last_active_at, created_at
) ON public.users TO anon, authenticated;

-- Profil güncellemeleri yalnızca izin verilen güvenli sütunlarla sınırlandırılmıştır
GRANT UPDATE (
    nickname, bio, photo_path, last_active_at
) ON public.users TO authenticated;

-- Kullanıcı oluşturma ve silme
GRANT INSERT (id, device_id, nickname, avatar_url, clan_id, bio) ON public.users TO authenticated;
GRANT DELETE ON public.users TO authenticated;

-- Kullanıcı Politikaları (RLS)
-- Güvenli Projeksiyon: Yalnızca sütun izni verilmiş alanlar üzerinden profil/liderlik listelemesi yapılabilir
CREATE POLICY users_select_public_profile ON public.users
    FOR SELECT TO anon, authenticated
    USING (true);

-- Kullanıcı Yalnız Kendi Profilini Ekleyebilir (Anon Auth Sahipliği)
CREATE POLICY users_insert_own ON public.users
    FOR INSERT TO authenticated
    WITH CHECK ((select auth.uid()) = id AND NOT is_demo);

-- Kullanıcı Yalnız Kendi Profilini Güncelleyebilir (Demo kayıtları korumalıdır)
CREATE POLICY users_update_own ON public.users
    FOR UPDATE TO authenticated
    USING ((select auth.uid()) = id AND NOT is_demo)
    WITH CHECK ((select auth.uid()) = id AND NOT is_demo);

-- Kullanıcı Yalnız Kendi Profilini Silebilir
CREATE POLICY users_delete_own ON public.users
    FOR DELETE TO authenticated
    USING ((select auth.uid()) = id AND NOT is_demo);

-- 5. Kullanıcı Envanteri (User Inventory)
-- Anon erişimi tamamen engellidir. Authenticated kullanıcı yalnızca kendi envanterini görebilir.
GRANT SELECT ON public.user_inventory TO authenticated;
CREATE POLICY user_inventory_select_own ON public.user_inventory
    FOR SELECT TO authenticated
    USING ((select auth.uid()) = user_id);

-- Envanter ekleme ve silme yalnızca server-side RPC (SECURITY DEFINER) ile yapılır
CREATE POLICY user_inventory_insert_own ON public.user_inventory
    FOR INSERT TO authenticated
    WITH CHECK ((select auth.uid()) = user_id);

-- 6. Aktiviteler (Activities)
-- Anon erişimi tamamen engellidir. Authenticated kullanıcı yalnızca kendi aktivitelerini görür/yazar.
GRANT SELECT, INSERT ON public.activities TO authenticated;
CREATE POLICY activities_select_own ON public.activities
    FOR SELECT TO authenticated
    USING ((select auth.uid()) = user_id);

CREATE POLICY activities_insert_own ON public.activities
    FOR INSERT TO authenticated
    WITH CHECK ((select auth.uid()) = user_id);

-- 7. İdempotent Olaylar (Processed Events)
-- Anon erişimi engellidir. Yalnızca oturum sahibi kendi olaylarını görebilir.
GRANT SELECT ON public.processed_events TO authenticated;
CREATE POLICY processed_events_select_own ON public.processed_events
    FOR SELECT TO authenticated
    USING ((select auth.uid()) = user_id);

-- 8. Durak Cooldownları (Transit Cooldowns)
-- Anon erişimi engellidir. Yalnızca oturum sahibi kendi cooldownlarını görebilir.
GRANT SELECT ON public.transit_cooldowns TO authenticated;
CREATE POLICY transit_cooldowns_select_own ON public.transit_cooldowns
    FOR SELECT TO authenticated
    USING ((select auth.uid()) = user_id);

-- 9. Admin & Sistem Bildirimleri (Admin Notifications Log)
GRANT SELECT ON public.admin_notifications_log TO authenticated;
CREATE POLICY admin_notifications_select_target ON public.admin_notifications_log
    FOR SELECT TO authenticated
    USING (
        target_type = 'all'
        OR (target_type = 'user' AND target_user_id = (select auth.uid()))
        OR (target_type = 'clan' AND target_clan_id = (SELECT clan_id FROM public.users WHERE id = (select auth.uid())))
    );

-- 10. Sunucu Adminleri Tablosu (Server Admins)
-- Anon erişimi engellidir. Yalnızca admin kullanıcının kendisi görebilir.
GRANT SELECT ON public.server_admins TO authenticated;
CREATE POLICY server_admins_select_own ON public.server_admins
    FOR SELECT TO authenticated
    USING ((select auth.uid()) = user_id);

-- 11. Görünümler (Views) İçin Erişim İzinleri
GRANT SELECT ON public.v_leaderboard_users TO anon, authenticated;
GRANT SELECT ON public.v_clan_leaderboard TO anon, authenticated;
GRANT SELECT ON public.v_clan_shame_board TO anon, authenticated;
GRANT SELECT ON public.v_global_shame_board TO anon, authenticated;



-- ============================================================================
-- 03_functions_and_rpc.sql
-- Atomik İşlemler, İdempotent Olaylar, 45dk Cooldown, Eşik Doğrulama ve Admin RPC
-- Proje: Green_Project (fhaxxraibydsjikxacbb)
-- ============================================================================

-- 1. Lig Kademesini Puan Eşiklerine Göre Hesaplama Fonksiyonu (STABLE)
CREATE OR REPLACE FUNCTION public.compute_league_tier(p_points INT, p_type VARCHAR)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        (SELECT tier FROM public.leagues
         WHERE league_type = p_type AND min_points <= p_points
         ORDER BY min_points DESC LIMIT 1),
        1
    );
$$;

-- 2. Kullanıcı Lig Kademesi Otomatik Tetikleyicisi
CREATE OR REPLACE FUNCTION public.trg_sync_user_league_tier()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.league_tier := public.compute_league_tier(NEW.weekly_points, 'individual');
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_league_tier ON public.users;
CREATE TRIGGER trg_users_league_tier
    BEFORE INSERT OR UPDATE OF weekly_points ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_sync_user_league_tier();

-- 3. Klan Lig Kademesi Otomatik Tetikleyicisi
CREATE OR REPLACE FUNCTION public.trg_sync_clan_league_tier()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.league_tier := public.compute_league_tier(NEW.weekly_points, 'clan');
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_clans_league_tier ON public.clans;
CREATE TRIGGER trg_clans_league_tier
    BEFORE INSERT OR UPDATE OF weekly_points ON public.clans
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_sync_clan_league_tier();

-- ============================================================================
-- RPC İŞLEM FONKSİYONLARI (SECURITY DEFINER + search_path sabitlemesi)
-- ============================================================================

-- 4. İlk Profil Senkronizasyonu & İstemci Bağlantısı (Legacy Yerel Veri Dahil)
CREATE OR REPLACE FUNCTION public.rpc_sync_initial_profile(
    p_device_id TEXT,
    p_nickname TEXT,
    p_clan_id INT DEFAULT NULL,
    p_avatar_url TEXT DEFAULT 'assets/avatars/user_sen.png',
    p_bio TEXT DEFAULT '',
    p_legacy_steps INT DEFAULT 0,
    p_legacy_points INT DEFAULT 0,
    p_legacy_gold INT DEFAULT 100,
    p_legacy_co2 NUMERIC DEFAULT 0.00,
    p_clan_name TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user RECORD;
    v_safe_points INT;
    v_safe_gold INT;
    v_safe_co2 NUMERIC;
    v_safe_steps INT;
    v_resolved_clan_id INT := NULL;
    v_streak INT := 0;
    v_streak_date DATE := NULL;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim: auth.uid() doğrulanamadı';
    END IF;

    -- Kullanıcı zaten kayıtlı mı kontrol et
    SELECT * INTO v_user FROM public.users WHERE id = v_user_id;

    IF FOUND THEN
        -- Kayıt zaten var: Mevcut sunucu durumunu dön (Sunucu gerçeğin tek kaynağıdır)
        RETURN jsonb_build_object(
            'ok', true,
            'is_new', false,
            'user', row_to_json(v_user)
        );
    END IF;

    -- Legacy yerel veriyi güvenli sınırlara tabi tut (Hile/Taşma Koruması)
    v_safe_points := LEAST(GREATEST(COALESCE(p_legacy_points, 0), 0), 25000);
    v_safe_gold   := LEAST(GREATEST(COALESCE(p_legacy_gold, 100), 100), 10000);
    v_safe_co2    := LEAST(GREATEST(COALESCE(p_legacy_co2, 0.00), 0.00), 200.00);
    v_safe_steps  := LEAST(GREATEST(COALESCE(p_legacy_steps, 0), 0), 50000);

    -- Klan ID çözümleme: Telefonda SQL'de olmayan klan varsa isme göre ara, yoksa NULL düş
    IF p_clan_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM public.clans WHERE id = p_clan_id) THEN
            v_resolved_clan_id := p_clan_id;
        ELSIF p_clan_name IS NOT NULL THEN
            SELECT id INTO v_resolved_clan_id FROM public.clans WHERE name = p_clan_name OR tag = p_clan_name LIMIT 1;
        END IF;
    ELSIF p_clan_name IS NOT NULL THEN
        SELECT id INTO v_resolved_clan_id FROM public.clans WHERE name = p_clan_name OR tag = p_clan_name LIMIT 1;
    END IF;

    -- 6.000 adım streak başlangıcı
    IF v_safe_steps >= 6000 THEN
        v_streak := 1;
        v_streak_date := CURRENT_DATE;
    END IF;

    -- Yeni kullanıcı kaydı oluştur
    INSERT INTO public.users (
        id, device_id, nickname, avatar_url, clan_id, bio,
        today_steps, weekly_points, all_time_points, gold_coins,
        streak_days, last_streak_date,
        weekly_saved_co2_kg, is_demo, last_active_at, created_at
    ) VALUES (
        v_user_id,
        COALESCE(NULLIF(TRIM(p_device_id), ''), 'DEV-' || v_user_id::text),
        COALESCE(NULLIF(TRIM(p_nickname), ''), 'Yeşil Gezgin'),
        COALESCE(NULLIF(TRIM(p_avatar_url), ''), 'assets/avatars/user_sen.png'),
        v_resolved_clan_id,
        SUBSTRING(COALESCE(p_bio, '') FROM 1 FOR 160),
        v_safe_steps,
        v_safe_points,
        v_safe_points,
        v_safe_gold,
        v_streak,
        v_streak_date,
        v_safe_co2,
        false,
        NOW(),
        NOW()
    )
    RETURNING * INTO v_user;

    -- Klan seçilmişse üye sayısını artır ve yeni gerçek kullanıcının puanını ekle
    IF v_resolved_clan_id IS NOT NULL THEN
        UPDATE public.clans
        SET member_count = member_count + 1,
            weekly_points = weekly_points + v_safe_points,
            all_time_points = all_time_points + v_safe_points,
            weekly_saved_co2_kg = weekly_saved_co2_kg + v_safe_co2
        WHERE id = v_resolved_clan_id;
    END IF;

    -- Başlangıç envanteri olarak standart avatar ver
    INSERT INTO public.user_inventory (user_id, item_slug)
    VALUES (v_user_id, 'ava_cycling_pro')
    ON CONFLICT DO NOTHING;

    RETURN jsonb_build_object(
        'ok', true,
        'is_new', true,
        'user', row_to_json(v_user)
    );
END;
$$;

-- 5. Kullanıcının Kendi Profilini, Envanterini ve Klanını Getiren Güvenli RPC
CREATE OR REPLACE FUNCTION public.rpc_get_my_profile()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user RECORD;
    v_clan RECORD;
    v_inventory JSONB;
    v_is_admin BOOLEAN := false;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim: auth.uid() doğrulanamadı';
    END IF;

    SELECT * INTO v_user FROM public.users WHERE id = v_user_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Kullanıcı profili bulunamadı');
    END IF;

    SELECT * INTO v_clan FROM public.clans WHERE id = v_user.clan_id;

    SELECT COALESCE(jsonb_agg(item_slug), '[]'::jsonb)
    INTO v_inventory
    FROM public.user_inventory
    WHERE user_id = v_user_id;

    SELECT EXISTS (SELECT 1 FROM public.server_admins WHERE user_id = v_user_id) INTO v_is_admin;

    RETURN jsonb_build_object(
        'ok', true,
        'user', row_to_json(v_user),
        'clan', CASE WHEN v_clan.id IS NOT NULL THEN row_to_json(v_clan) ELSE NULL END,
        'inventory', v_inventory,
        'is_admin', v_is_admin
    );
END;
$$;

-- 6. Profil Bilgilerini Güncelleme RPC (Sahiplik & 160 Karakter Bio Sınırı)
CREATE OR REPLACE FUNCTION public.rpc_update_profile(
    p_nickname TEXT,
    p_bio TEXT DEFAULT NULL,
    p_photo_path TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_clean_nick TEXT;
    v_clean_bio TEXT;
    v_user RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    SELECT * INTO v_user FROM public.users WHERE id = v_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kullanıcı bulunamadı';
    END IF;
    IF v_user.is_demo THEN
        RAISE EXCEPTION 'Demo profiller değiştirilemez';
    END IF;

    v_clean_nick := TRIM(COALESCE(p_nickname, v_user.nickname));
    IF LENGTH(v_clean_nick) < 2 OR LENGTH(v_clean_nick) > 50 THEN
        RAISE EXCEPTION 'Geçersiz isim uzunluğu (2-50 karakter)';
    END IF;

    IF p_bio IS NOT NULL THEN
        v_clean_bio := SUBSTRING(TRIM(p_bio) FROM 1 FOR 160);
    ELSE
        v_clean_bio := v_user.bio;
    END IF;

    UPDATE public.users
    SET nickname = v_clean_nick,
        bio = v_clean_bio,
        photo_path = COALESCE(p_photo_path, photo_path),
        last_active_at = NOW()
    WHERE id = v_user_id
    RETURNING * INTO v_user;

    RETURN jsonb_build_object('ok', true, 'user', row_to_json(v_user));
END;
$$;

-- 7. Klana Katılma / Klan Değiştirme RPC
CREATE OR REPLACE FUNCTION public.rpc_join_clan(p_clan_id INT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_old_clan_id INT;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clans WHERE id = p_clan_id) THEN
        RAISE EXCEPTION 'Geçersiz klan seçimi';
    END IF;

    SELECT clan_id INTO v_old_clan_id FROM public.users WHERE id = v_user_id;

    IF v_old_clan_id = p_clan_id THEN
        RETURN jsonb_build_object('ok', true, 'message', 'Zaten bu klandasınız', 'clan_id', p_clan_id);
    END IF;

    -- Eski klandan üye düş
    IF v_old_clan_id IS NOT NULL THEN
        UPDATE public.clans
        SET member_count = GREATEST(member_count - 1, 0)
        WHERE id = v_old_clan_id;
    END IF;

    -- Yeni klana üye ekle
    UPDATE public.clans
    SET member_count = member_count + 1
    WHERE id = p_clan_id;

    -- Kullanıcı klanını güncelle
    UPDATE public.users
    SET clan_id = p_clan_id,
        last_active_at = NOW()
    WHERE id = v_user_id;

    RETURN jsonb_build_object('ok', true, 'new_clan_id', p_clan_id);
END;
$$;

-- 8. İdempotent Adım Ekleme & Sunucu Doğrulamalı Puanlama RPC
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
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    IF p_event_id IS NULL OR TRIM(p_event_id) = '' THEN
        RAISE EXCEPTION 'event_id boş olamaz';
    END IF;

    -- Eşzamanlı çağrılarda yarış durumunu engellemek için kullanıcı+event bazlı işlem kilidi
    PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || ':' || p_event_id));

    -- İdempotency Kontrolü: Olay daha önce işlendi mi?
    SELECT * INTO v_cached
    FROM public.processed_events
    WHERE user_id = v_user_id AND event_id = p_event_id;

    IF FOUND THEN
        RETURN v_cached.result_json || jsonb_build_object('duplicate', true);
    END IF;

    -- Değer doğrulama sınırları (Aşırı veya geçersiz girdi ret)
    IF p_step_count IS NULL OR p_step_count <= 0 OR p_step_count > 50000 THEN
        RAISE EXCEPTION 'Geçersiz adım sayısı: %', p_step_count;
    END IF;
    IF p_distance_km IS NULL OR p_distance_km < 0 OR p_distance_km > 100 OR p_distance_km != p_distance_km THEN
        RAISE EXCEPTION 'Geçersiz mesafe miktarı';
    END IF;

    -- Kullanıcı satırını atomik kilitle
    SELECT * INTO v_user FROM public.users WHERE id = v_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kullanıcı bulunamadı';
    END IF;

    -- Gün değişmişse bugünkü adımları sıfırdan başlat
    IF v_user.last_active_at::date < CURRENT_DATE THEN
        v_base_steps := 0;
        IF v_user.last_streak_date < CURRENT_DATE - INTERVAL '1 day' THEN
            v_streak := 0;
        ELSE
            v_streak := v_user.streak_days;
        END IF;
    ELSE
        v_base_steps := v_user.today_steps;
        v_streak := v_user.streak_days;
    END IF;

    v_new_today_steps := v_base_steps + p_step_count;

    -- Sunucu Tarafı Puanlama: Her tamamlanan 1.000 adım = 5 puan (İstemci parametresine güvenilmez)
    v_points_awarded := ((v_new_today_steps / 1000) - (v_base_steps / 1000)) * 5;
    IF v_points_awarded < 0 THEN
        v_points_awarded := 0;
    END IF;

    -- Sunucu Tarafı CO₂ Tasarrufu Hesaplama: Mesafe × 0.19 kg/km
    v_co2_saved := ROUND(GREATEST(p_distance_km, 0) * 0.19, 2);

    -- 6.000 Adım Streak Kuralı (REVIZYON_02 ile tutarlı)
    IF v_new_today_steps >= 6000 AND (v_user.last_streak_date IS NULL OR v_user.last_streak_date < CURRENT_DATE) THEN
        IF v_user.last_streak_date = CURRENT_DATE - INTERVAL '1 day' THEN
            v_streak := v_streak + 1;
        ELSE
            v_streak := 1;
        END IF;
        v_last_streak_date := CURRENT_DATE;
    ELSE
        v_last_streak_date := v_user.last_streak_date;
    END IF;

    -- 1. Aktivite loguna yaz
    INSERT INTO public.activities (
        event_id, user_id, activity_type, steps_count,
        distance_km, points_earned, co2_delta_kg,
        verification_status, feedback_message, created_at
    ) VALUES (
        p_event_id, v_user_id, 'walk', p_step_count,
        p_distance_km, v_points_awarded, v_co2_saved,
        'verified', 'Yürüyüş adımları başarıyla kaydedildi.', NOW()
    );

    -- 2. Kullanıcı bakiyesini ve sayaçlarını güncelle
    UPDATE public.users
    SET today_steps = v_new_today_steps,
        weekly_points = weekly_points + v_points_awarded,
        all_time_points = all_time_points + v_points_awarded,
        weekly_saved_co2_kg = weekly_saved_co2_kg + v_co2_saved,
        streak_days = v_streak,
        last_streak_date = v_last_streak_date,
        last_active_at = NOW()
    WHERE id = v_user_id;

    -- 3. Klan toplamını atomik olarak güncelle
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

    -- 4. Olayı idempotency tablosuna kaydet
    INSERT INTO public.processed_events (user_id, event_id, event_type, result_json)
    VALUES (v_user_id, p_event_id, 'step_sync', v_res);

    RETURN v_res;
END;
$$;

-- 9. İdempotent ve 45 Dakika Cooldown Korumalı Toplu Taşıma Okutma RPC (Ortak QR/NFC)
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
    v_last_scan TIMESTAMPTZ;
    v_raw_code TEXT;
    v_canonical_stop TEXT;
    v_clan_id INT;
    v_rem_sec INT;
    v_res JSONB;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    IF p_event_id IS NULL OR TRIM(p_event_id) = '' THEN
        RAISE EXCEPTION 'event_id boş olamaz';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || ':' || p_event_id));

    -- İdempotency kontrolü
    SELECT * INTO v_cached
    FROM public.processed_events
    WHERE user_id = v_user_id AND event_id = p_event_id;

    IF FOUND THEN
        RETURN v_cached.result_json || jsonb_build_object('duplicate', true);
    END IF;

    -- Durak kodunu ve URI yükünü kanonikleştir (QR ve NFC aynı durağa eşlenir)
    v_raw_code := TRIM(COALESCE(p_stop_code, ''));
    v_canonical_stop := v_raw_code;
    IF v_canonical_stop LIKE 'YESILADIM://TRANSIT/%' THEN
        v_canonical_stop := split_part(substring(v_canonical_stop from 21), '?', 1);
    ELSIF v_canonical_stop LIKE '%?%' THEN
        v_canonical_stop := split_part(v_canonical_stop, '?', 1);
    END IF;
    v_canonical_stop := UPPER(TRIM(v_canonical_stop));

    SELECT * INTO v_stop
    FROM public.transit_stops
    WHERE UPPER(stop_code) = v_canonical_stop
       OR UPPER(nfc_uid) = UPPER(v_raw_code)
       OR qr_payload = v_raw_code
       OR qr_payload LIKE (v_raw_code || '%')
       OR UPPER(stop_code) = UPPER(v_raw_code)
    LIMIT 1;

    IF v_stop.id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Geçersiz veya bilinmeyen durak kodu');
    END IF;

    -- Cooldown kontrolü: Şartname gereği tam 45 DAKİKA (QR ve NFC ortak kanonik durak)
    SELECT last_scanned_at INTO v_last_scan
    FROM public.transit_cooldowns
    WHERE user_id = v_user_id AND stop_code = v_stop.stop_code;

    IF v_last_scan IS NOT NULL AND (NOW() - v_last_scan) < INTERVAL '45 minutes' THEN
        v_rem_sec := CEIL(EXTRACT(EPOCH FROM (v_last_scan + INTERVAL '45 minutes' - NOW())));
        v_res := jsonb_build_object(
            'ok', false,
            'cooldown', true,
            'remaining_seconds', v_rem_sec,
            'message', 'Aynı otobüsü iki kere mi satın aldın? Sonraki biniş puanı için ' || CEIL(v_rem_sec / 60.0)::TEXT || ' dk bekle!'
        );
        RETURN v_res;
    END IF;

    -- Cooldown kaydını güncelle
    INSERT INTO public.transit_cooldowns (user_id, stop_code, last_scanned_at)
    VALUES (v_user_id, v_stop.stop_code, NOW())
    ON CONFLICT (user_id, stop_code)
    DO UPDATE SET last_scanned_at = NOW();

    -- Aktivite logu oluştur (Sunucu veritabanı puan ve tasarruf değerini kullanır)
    INSERT INTO public.activities (
        event_id, user_id, activity_type, distance_km,
        transit_stop_id, points_earned, co2_delta_kg,
        verification_status, feedback_message, created_at
    ) VALUES (
        p_event_id, v_user_id, 'public_transit', v_stop.avg_trip_km,
        v_stop.id, v_stop.points_reward, v_stop.co2_saved_per_trip_kg,
        'verified', v_stop.route_name || ' doğrulandı (' || p_verification_method || ').', NOW()
    );

    -- Kullanıcı puan ve co2 güncelle
    UPDATE public.users
    SET weekly_points = weekly_points + v_stop.points_reward,
        all_time_points = all_time_points + v_stop.points_reward,
        weekly_saved_co2_kg = weekly_saved_co2_kg + v_stop.co2_saved_per_trip_kg,
        last_active_at = NOW()
    WHERE id = v_user_id
    RETURNING clan_id INTO v_clan_id;

    -- Klan puan ve co2 güncelle
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

-- 10. Bisiklet Sürüşü & Hız/İvme Doğrulama RPC (bike50ve35 / 25variance0.12 / 0.19 Tasarruf)
CREATE OR REPLACE FUNCTION public.rpc_record_bike(
    p_event_id TEXT,
    p_distance_km NUMERIC,
    p_avg_speed_kmh NUMERIC,
    p_max_speed_kmh NUMERIC,
    p_accel_variance NUMERIC DEFAULT NULL,
    p_points_earned INT DEFAULT NULL,
    p_co2_saved_kg NUMERIC DEFAULT NULL,
    p_is_spoof BOOLEAN DEFAULT FALSE,
    p_reject_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_cached RECORD;
    v_clan_id INT;
    v_points INT;
    v_co2_saved NUMERIC(8,2);
    v_wasted_co2 NUMERIC(8,2);
    v_res JSONB;
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

    -- Geçersiz veri sınırları
    IF p_distance_km IS NULL OR p_distance_km <= 0 OR p_distance_km > 300 OR p_distance_km != p_distance_km
       OR p_avg_speed_kmh IS NULL OR p_avg_speed_kmh < 0
       OR p_max_speed_kmh IS NULL OR p_max_speed_kmh < 0 THEN
        RETURN jsonb_build_object('ok', false, 'message', 'Geçersiz sürüş verisi.');
    END IF;

    -- KAPISI 1: Hız Reddi (max >= 50 km/sa VEYA ortalama >= 35 km/sa)
    -- Puan verilmez, Utanç Tablosu cezası UYGULANMAZ (hız hilesi reddidir)
    IF p_is_spoof OR p_max_speed_kmh >= 50.0 OR p_avg_speed_kmh >= 35.0 THEN
        INSERT INTO public.activities (
            event_id, user_id, activity_type, distance_km,
            avg_speed_kmh, max_speed_kmh, accel_variance,
            points_earned, co2_delta_kg, verification_status,
            feedback_message, created_at
        ) VALUES (
            p_event_id, v_user_id, 'bike', p_distance_km,
            p_avg_speed_kmh, p_max_speed_kmh, p_accel_variance,
            0, 0.00, 'rejected_speed_spoof',
            COALESCE(p_reject_reason, '❌ Hız reddi: Saatte 50 km giden bisiklet olmaz! Aktivite reddedildi.'), NOW()
        );

        v_res := jsonb_build_object(
            'ok', false,
            'rejected', true,
            'reason', COALESCE(p_reject_reason, '❌ Hız reddi: Saatte 50 km giden bisiklet olmaz! Aktivite reddedildi (puan verilmedi, Utanç Tablosu cezası uygulanmadı).')
        );

    -- KAPISI 2: Araba Şüphesi (Hız > 25 km/sa ve İvme Varyansı < 0.12 - titreşimsiz pürüzsüz taşıt sürüşü)
    -- Aktivite puanı verilmez. Haftalık araba/taksi sayacına +1 eklenir ve mesafe × 0.192 kg harcanan CO₂ Utanç Tablosuna işlenir.
    ELSIF p_avg_speed_kmh > 25.0 AND p_accel_variance IS NOT NULL AND p_accel_variance >= 0 AND p_accel_variance < 0.12 THEN
        v_wasted_co2 := ROUND(p_distance_km * 0.192, 2);

        INSERT INTO public.activities (
            event_id, user_id, activity_type, distance_km,
            avg_speed_kmh, max_speed_kmh, accel_variance,
            points_earned, co2_delta_kg, verification_status,
            feedback_message, created_at
        ) VALUES (
            p_event_id, v_user_id, 'bike', p_distance_km,
            p_avg_speed_kmh, p_max_speed_kmh, p_accel_variance,
            0, -v_wasted_co2, 'shame_logged',
            '🚨 Araba şüphesi: Düşük titreşim varyansı (<0.12). Utanç Tablosuna yazıldı.', NOW()
        );

        UPDATE public.users
        SET weekly_car_taxi_trips = weekly_car_taxi_trips + 1,
            weekly_car_taxi_km = weekly_car_taxi_km + p_distance_km,
            weekly_wasted_co2_kg = weekly_wasted_co2_kg + v_wasted_co2,
            last_active_at = NOW()
        WHERE id = v_user_id
        RETURNING clan_id INTO v_clan_id;

        IF v_clan_id IS NOT NULL THEN
            UPDATE public.clans
            SET weekly_wasted_co2_kg = weekly_wasted_co2_kg + v_wasted_co2
            WHERE id = v_clan_id;
        END IF;

        v_res := jsonb_build_object(
            'ok', false,
            'penalty', true,
            'wasted_co2_kg', v_wasted_co2,
            'reason', '🚨 Araba şüphesi (titreşimsiz ivme: varyans < 0.12): Aktivite puanı verilmedi. Haftalık araba/taksi sayacına +1 eklendi ve ' || v_wasted_co2::TEXT || ' kg harcanan CO₂ Utanç Tablosu siciline işlendi.'
        );

    -- KAPISI 3: Geçerli Sürüş Onayı (Sunucu Puanı: FLOOR(km), Sunucu Tasarrufu: km × 0.19 kg)
    ELSE
        v_points := FLOOR(p_distance_km)::INT;
        v_co2_saved := ROUND(p_distance_km * 0.19, 2);

        INSERT INTO public.activities (
            event_id, user_id, activity_type, distance_km,
            avg_speed_kmh, max_speed_kmh, accel_variance,
            points_earned, co2_delta_kg, verification_status,
            feedback_message, created_at
        ) VALUES (
            p_event_id, v_user_id, 'bike', p_distance_km,
            p_avg_speed_kmh, p_max_speed_kmh, p_accel_variance,
            v_points, v_co2_saved, 'verified',
            'Bisiklet sürüşü onaylandı.', NOW()
        );

        UPDATE public.users
        SET weekly_points = weekly_points + v_points,
            all_time_points = all_time_points + v_points,
            weekly_saved_co2_kg = weekly_saved_co2_kg + v_co2_saved,
            last_active_at = NOW()
        WHERE id = v_user_id
        RETURNING clan_id INTO v_clan_id;

        IF v_clan_id IS NOT NULL THEN
            UPDATE public.clans
            SET weekly_points = weekly_points + v_points,
                all_time_points = all_time_points + v_points,
                weekly_saved_co2_kg = weekly_saved_co2_kg + v_co2_saved
            WHERE id = v_clan_id;
        END IF;

        v_res := jsonb_build_object(
            'ok', true,
            'points_awarded', v_points,
            'co2_saved_kg', v_co2_saved
        );
    END IF;

    INSERT INTO public.processed_events (user_id, event_id, event_type, result_json)
    VALUES (v_user_id, p_event_id, 'bike_session', v_res);

    RETURN v_res;
END;
$$;

-- 11. Araba / Taksi İsraf ve Utanç Tablosu Ceza Kaydı RPC (Son 45 Dk Transit Muafiyeti + 0.192kg)
CREATE OR REPLACE FUNCTION public.rpc_record_vehicle_penalty(
    p_event_id TEXT,
    p_distance_km NUMERIC,
    p_wasted_co2_kg NUMERIC DEFAULT NULL,
    p_avg_speed_kmh NUMERIC DEFAULT 0.00
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_cached RECORD;
    v_clan_id INT;
    v_is_exempt BOOLEAN := false;
    v_wasted NUMERIC(8,2);
    v_res JSONB;
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

    IF p_distance_km IS NULL OR p_distance_km <= 0 OR p_distance_km > 500 OR p_distance_km != p_distance_km THEN
        RAISE EXCEPTION 'Geçersiz mesafe ölçümü';
    END IF;

    -- Muafiyet Kapısı: Son 45 dk içinde toplu taşıma kaydı varsa ceza muafiyeti uygulanır
    SELECT EXISTS (
        SELECT 1 FROM public.transit_cooldowns
        WHERE user_id = v_user_id
          AND last_scanned_at >= NOW() - INTERVAL '45 minutes'
    ) INTO v_is_exempt;

    IF v_is_exempt THEN
        v_res := jsonb_build_object(
            'ok', true,
            'exempt', true,
            'message', 'Son 45 dk içinde toplu taşıma kaydın olduğu için araba/taksi muafiyeti devrede; ceza uygulanmadı.'
        );

        INSERT INTO public.processed_events (user_id, event_id, event_type, result_json)
        VALUES (v_user_id, p_event_id, 'vehicle_penalty', v_res);

        RETURN v_res;
    END IF;

    -- Sunucu Tarafı Harcanan CO₂: Mesafe × 0.192 kg/km
    v_wasted := ROUND(p_distance_km * 0.192, 2);

    -- Aktiviteye utanç kaydı yaz
    INSERT INTO public.activities (
        event_id, user_id, activity_type, distance_km,
        avg_speed_kmh, points_earned, co2_delta_kg,
        verification_status, feedback_message, created_at
    ) VALUES (
        p_event_id, v_user_id, 'car_taxi_penalty', p_distance_km,
        p_avg_speed_kmh, 0, -v_wasted,
        'shame_logged', 'Özel araç/taksi kullanımı tespit edildi. Utanç tablosuna işlendi.', NOW()
    );

    -- Kullanıcı ceza sayaçlarını artır
    UPDATE public.users
    SET weekly_car_taxi_trips = weekly_car_taxi_trips + 1,
        weekly_car_taxi_km = weekly_car_taxi_km + p_distance_km,
        weekly_wasted_co2_kg = weekly_wasted_co2_kg + v_wasted,
        last_active_at = NOW()
    WHERE id = v_user_id
    RETURNING clan_id INTO v_clan_id;

    -- Klan israf sayacını artır
    IF v_clan_id IS NOT NULL THEN
        UPDATE public.clans
        SET weekly_wasted_co2_kg = weekly_wasted_co2_kg + v_wasted
        WHERE id = v_clan_id;
    END IF;

    v_res := jsonb_build_object(
        'ok', true,
        'shame_logged', true,
        'wasted_co2_kg', v_wasted,
        'trips_added', 1
    );

    INSERT INTO public.processed_events (user_id, event_id, event_type, result_json)
    VALUES (v_user_id, p_event_id, 'vehicle_penalty', v_res);

    RETURN v_res;
END;
$$;

-- 12. Mağazadan Altın İle Kozmetik Satın Alma RPC (Atomik Bakiye ve Envanter Kontrolü)
CREATE OR REPLACE FUNCTION public.rpc_buy_shop_item(p_item_slug TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_item RECORD;
    v_user RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    -- Ürünü kontrol et
    SELECT * INTO v_item FROM public.shop_items WHERE item_slug = p_item_slug;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Mağaza ürünü bulunamadı: %', p_item_slug;
    END IF;

    -- Zaten sahip mi?
    IF EXISTS (SELECT 1 FROM public.user_inventory WHERE user_id = v_user_id AND item_slug = p_item_slug) THEN
        RAISE EXCEPTION 'Bu ürüne zaten sahipsiniz';
    END IF;

    -- Kullanıcının altını yeterli mi? (FOR UPDATE ile kilit)
    SELECT * INTO v_user FROM public.users WHERE id = v_user_id FOR UPDATE;
    IF v_user.gold_coins < v_item.price_gold THEN
        RAISE EXCEPTION 'Yetersiz altın! Gerekli: %, Mevcut: %', v_item.price_gold, v_user.gold_coins;
    END IF;

    -- Altını düş
    UPDATE public.users
    SET gold_coins = gold_coins - v_item.price_gold,
        last_active_at = NOW()
    WHERE id = v_user_id;

    -- Envantere ekle
    INSERT INTO public.user_inventory (user_id, item_slug)
    VALUES (v_user_id, p_item_slug);

    RETURN jsonb_build_object(
        'ok', true,
        'item_slug', p_item_slug,
        'price_paid', v_item.price_gold,
        'remaining_gold', v_user.gold_coins - v_item.price_gold
    );
END;
$$;

-- 13. Kozmetik Kuşanma (Equip) RPC
CREATE OR REPLACE FUNCTION public.rpc_equip_shop_item(p_item_slug TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_item RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    -- Çıkarma durumu (none veya default)
    IF p_item_slug IN ('none', 'frame_none', 'pet_none', 'default_avatar') THEN
        IF p_item_slug = 'default_avatar' THEN
            UPDATE public.users SET avatar_url = 'assets/avatars/user_sen.png' WHERE id = v_user_id;
        ELSIF p_item_slug LIKE '%frame%' OR p_item_slug = 'none' THEN
            UPDATE public.users SET frame_slug = 'none' WHERE id = v_user_id;
        ELSIF p_item_slug LIKE '%pet%' THEN
            UPDATE public.users SET pet_slug = 'none' WHERE id = v_user_id;
        END IF;
        RETURN jsonb_build_object('ok', true, 'equipped', p_item_slug);
    END IF;

    -- Envanter sahipliği kontrolü
    IF NOT EXISTS (SELECT 1 FROM public.user_inventory WHERE user_id = v_user_id AND item_slug = p_item_slug) THEN
        RAISE EXCEPTION 'Bu eşyaya henüz sahip değilsiniz';
    END IF;

    SELECT * INTO v_item FROM public.shop_items WHERE item_slug = p_item_slug;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bilinmeyen eşya kategorisi';
    END IF;

    IF v_item.category = 'avatar' THEN
        UPDATE public.users SET avatar_url = v_item.asset_preview WHERE id = v_user_id;
    ELSIF v_item.category = 'frame' THEN
        UPDATE public.users SET frame_slug = v_item.item_slug WHERE id = v_user_id;
    ELSIF v_item.category = 'pet' THEN
        UPDATE public.users SET pet_slug = v_item.item_slug WHERE id = v_user_id;
    END IF;

    RETURN jsonb_build_object('ok', true, 'category', v_item.category, 'equipped', p_item_slug);
END;
$$;

-- 14. Haftalık Sıfırlama ve Şampiyon Belirleme RPC (Idempotent: Haftada Yalnız 1 Kez)
CREATE OR REPLACE FUNCTION public.rpc_admin_trigger_weekly_reset()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_is_service_role BOOLEAN := false;
    v_week_id TEXT;
    v_week_label TEXT;
    v_top_user RECORD;
    v_top_clan RECORD;
    v_total_co2 NUMERIC(10,2);
    v_affected_users INT;
    v_affected_clans INT;
BEGIN
    -- Yetki kontrolü: server_admins tablosu VEYA service_role JWT rolü
    BEGIN
        v_is_service_role := ((current_setting('request.jwt.claims', true)::jsonb ->> 'role') = 'service_role');
    EXCEPTION WHEN OTHERS THEN
        v_is_service_role := false;
    END;

    IF NOT v_is_service_role AND (v_caller_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.server_admins WHERE user_id = v_caller_id)) THEN
        RAISE EXCEPTION 'Yetkisiz erişim: Bu işlem yalnızca sunucu yöneticileri tarafından yürütülebilir.';
    END IF;

    -- Haftalık Idempotency: Aynı hafta birden fazla kez sıfırlanamaz!
    v_week_id := TO_CHAR(NOW(), 'IYYY-"W"IW');

    IF EXISTS (SELECT 1 FROM public.weekly_champions WHERE week_id = v_week_id) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'already_settled', true,
            'message', 'Bu hafta (' || v_week_id || ') zaten sıfırlandı ve şampiyonlar ilan edildi.'
        );
    END IF;

    -- 1. Haftanın en yüksek puanlı bireysel şampiyonunu ve klanını sıfırlama ÖNCESİ belirle
    SELECT id, nickname, weekly_points INTO v_top_user
    FROM public.users
    ORDER BY weekly_points DESC, today_steps DESC
    LIMIT 1;

    SELECT id, name, weekly_points INTO v_top_clan
    FROM public.clans
    ORDER BY weekly_points DESC
    LIMIT 1;

    SELECT COALESCE(SUM(weekly_saved_co2_kg), 0) INTO v_total_co2 FROM public.clans;

    v_week_label := TO_CHAR(NOW() - INTERVAL '7 days', 'DD Mon') || ' - ' || TO_CHAR(NOW(), 'DD Mon YYYY') || ' Haftası';

    -- 2. Şampiyonlar vitrinine ekle
    INSERT INTO public.weekly_champions (
        week_id, week_label, champion_user_id, champion_user_points,
        champion_clan_id, champion_clan_points,
        total_community_saved_co2_kg, announced_at
    ) VALUES (
        v_week_id, v_week_label,
        v_top_user.id, COALESCE(v_top_user.weekly_points, 0),
        v_top_clan.id, COALESCE(v_top_clan.weekly_points, 0),
        v_total_co2, NOW()
    );

    -- 3. Kullanıcıların haftalık puanlarını Altına dönüştür ve haftalık sayaçları sıfırla
    -- NOT: Günlük adım ve streak korunur! Sadece haftalık alanlar sıfırlanır.
    UPDATE public.users
    SET gold_coins = gold_coins + weekly_points,
        weekly_points = 0,
        weekly_saved_co2_kg = 0,
        weekly_wasted_co2_kg = 0,
        weekly_car_taxi_trips = 0,
        weekly_car_taxi_km = 0;
    GET DIAGNOSTICS v_affected_users = ROW_COUNT;

    -- 4. Klanların haftalık puanlarını sıfırla
    UPDATE public.clans
    SET weekly_points = 0,
        weekly_saved_co2_kg = 0,
        weekly_wasted_co2_kg = 0;
    GET DIAGNOSTICS v_affected_clans = ROW_COUNT;

    RETURN jsonb_build_object(
        'ok', true,
        'week_id', v_week_id,
        'week_label', v_week_label,
        'champion_user', v_top_user.nickname,
        'champion_user_points', v_top_user.weekly_points,
        'champion_clan', v_top_clan.name,
        'champion_clan_points', v_top_clan.weekly_points,
        'total_community_saved_co2_kg', v_total_co2,
        'users_reset', v_affected_users,
        'clans_reset', v_affected_clans
    );
END;
$$;

-- 15. Admin Canlı Bildirim Gönderme RPC (Realtime Kuyruğuna Yazar)
CREATE OR REPLACE FUNCTION public.rpc_admin_send_notification(
    p_target_type TEXT,
    p_target_user_id UUID DEFAULT NULL,
    p_target_clan_id INT DEFAULT NULL,
    p_template_code TEXT DEFAULT NULL,
    p_title TEXT DEFAULT 'Bildirim',
    p_message_body TEXT DEFAULT '',
    p_severity TEXT DEFAULT 'savage'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_is_service_role BOOLEAN := false;
    v_new_id INT;
BEGIN
    BEGIN
        v_is_service_role := ((current_setting('request.jwt.claims', true)::jsonb ->> 'role') = 'service_role');
    EXCEPTION WHEN OTHERS THEN
        v_is_service_role := false;
    END;

    IF NOT v_is_service_role AND (v_caller_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.server_admins WHERE user_id = v_caller_id)) THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    INSERT INTO public.admin_notifications_log (
        target_type, target_user_id, target_clan_id,
        template_code, title, message_body, severity,
        is_delivered, created_at
    ) VALUES (
        p_target_type, p_target_user_id, p_target_clan_id,
        p_template_code, p_title, p_message_body, p_severity,
        true, NOW()
    )
    RETURNING id INTO v_new_id;

    RETURN jsonb_build_object('ok', true, 'notification_id', v_new_id);
END;
$$;

-- ============================================================================
-- GÜVENLİK YETKİLENDİRMELERİ (REVOKE & EXPLICIT GRANT)
-- En az yetki ilkesi: Admin ve sistem fonksiyonları authenticated/anon'a verilmez
-- ============================================================================
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM anon;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM authenticated;

-- Kamusal yardımcı fonksiyon
GRANT EXECUTE ON FUNCTION public.compute_league_tier(INT, VARCHAR) TO anon, authenticated;

-- Kullanıcı oturum RPC'leri (Authenticated Only)
GRANT EXECUTE ON FUNCTION public.rpc_sync_initial_profile TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_my_profile TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_update_profile TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_join_clan TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_record_steps TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_record_transit TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_record_bike TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_record_vehicle_penalty TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_buy_shop_item TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_equip_shop_item TO authenticated;

-- Yönetici ve Sistem RPC'leri (Yalnızca service_role / Edge Function yetkilidir!)
GRANT EXECUTE ON FUNCTION public.rpc_admin_trigger_weekly_reset TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_admin_send_notification TO service_role;



-- ============================================================================
-- 04_seed_data.sql
-- İdempotent Referans ve Başlangıç Verileri (Ligler, 11 Klan, 20 Kullanıcı, Duraklar, Ürünler)
-- Proje: Green_Project (fhaxxraibydsjikxacbb)
-- ============================================================================

-- 1. Ligler (Bireysel ve Klan Ligleri)
INSERT INTO public.leagues (league_type, tier, name, min_points, badge_slug, color_hex, description)
VALUES
('individual', 1, 'Karbonmonoksit', 0,     'ind_tier_1_co',       '#8C8275', 'Başlangıç seviyesi. Egzoz dumanından yeni çıkıyoruz!'),
('individual', 2, 'Karbondioksit',  150,   'ind_tier_2_co2',      '#8B5A2B', 'Adımlar hızlandı, fabrika bacalarını geride bırakıyoruz.'),
('individual', 3, 'Azot',           350,   'ind_tier_3_n2',       '#4A6070', 'Atmosferin dengesini koruyan istikrarlı yürüyüşçüler.'),
('individual', 4, 'Oksijen',        650,   'ind_tier_4_o2',       '#2CE5B5', 'Şehre nefes aldıran, toplu taşıma ve bisiklet tutkunları.'),
('individual', 5, 'Ozon',           1100,  'ind_tier_5_o3',       '#5B6EE1', 'Gezegenin koruyucu kalkanı! Karbon ayak izi minimumda.'),
('individual', 6, 'Sönmez Biyosfer',1800,  'ind_tier_6_biosfer',  '#589A42', 'Efsanevi ekosistem liderleri. Sıfır emisyon şampiyonları!'),
('clan', 1, 'Kül Birliği',          0,     'clan_tier_1_kul',     '#8C8275', 'Henüz kıvılcım aşamasındaki topluluklar.'),
('clan', 2, 'Sis Loncası',          2500,  'clan_tier_2_sis',     '#8B5A2B', 'Sisi dağıtmaya başlayan organize ekipler.'),
('clan', 3, 'Akım Cephesi',        6000,  'clan_tier_3_nefes',   '#4A6070', 'Rüzgarı ve hareketi arkasına alan organize klanlar.'),
('clan', 4, 'Koruyucu İttifak',     12000, 'clan_tier_4_ittifak', '#2CE5B5', 'Yeşil dönüşümü sırtlayan güçlü topluluklar.'),
('clan', 5, 'Ozon Muhafızları',     25000, 'clan_tier_5_ozon',    '#5B6EE1', 'Atmosferi koruyan elit klanlar ligi.'),
('clan', 6, 'Biyosfer Konseyi',     50000, 'clan_tier_6_konsey',  '#589A42', 'Türkiye''nin en yeşil ve yenilmez zirve toplulukları!')
ON CONFLICT (league_type, tier) DO UPDATE SET
    name = EXCLUDED.name,
    min_points = EXCLUDED.min_points,
    badge_slug = EXCLUDED.badge_slug,
    color_hex = EXCLUDED.color_hex,
    description = EXCLUDED.description;

-- 2. Klanlar (11 Referans Klan - Puan Eşiklerine Göre Doğrulanmış Lig Kademeleri)
-- KTÜ Kanuni (125k), OF (98k), ODTÜ (87k), Koç (76k), Sabancı (69k), İTÜ (54k) >= 50k -> Tier 6
-- YTÜ (48k), Gazi (42k), KTÜDAK (38k), Sincan (29k) >= 25k -> Tier 5
-- Kırıkkale (18k) >= 12k -> Tier 4
INSERT INTO public.clans (id, name, tag, logo_url, league_tier, weekly_points, all_time_points, weekly_saved_co2_kg, weekly_wasted_co2_kg, member_count)
VALUES
(1,  'KTÜ Kanuni',          'KTÜ-K',  'assets/clans/ktu_kanuni.png', 6, 125430, 480200, 312.40, 14.20, 142),
(2,  'KTÜ OF',              'KTÜ-OF', 'assets/clans/ktu_of.png',     6, 98210,  365000, 245.80, 18.50, 98),
(3,  'ODTÜ',                'ODTU',   'assets/clans/odtu.png',       6, 87540,  410500, 218.00, 22.10, 115),
(4,  'Koç Üni',             'KOC',    'assets/clans/koc.png',        6, 76320,  290100, 184.50, 45.80, 84),
(5,  'Sabancı Üni',         'SU',     'assets/clans/sabanci.png',    6, 69430,  255400, 162.30, 39.40, 76),
(6,  'İTÜ',                 'ITU',    'assets/clans/itu.png',        6, 54210,  310000, 138.90, 25.00, 92),
(7,  'YTÜ',                 'YTU',    'assets/clans/ytu.png',        5, 48960,  198000, 119.20, 19.80, 68),
(8,  'Gazi Üni',            'GAZİ',   'assets/clans/gazi.png',       5, 42180,  175300, 104.60, 21.30, 61),
(9,  'KTÜ Dağcılık Kulübü', 'KTÜDAK', 'assets/clans/ktudak.png',     5, 38450,  142000, 98.40,  2.10,  34),
(10, 'Sincanlılar Derneği', '06SNC',  'assets/clans/sincan.png',     5, 29800,  112000, 74.20,  31.50, 45),
(11, 'Kırıkkale_45',        '71_45',  'assets/clans/kirikkale.png',  4, 18400,  64500,  42.10,  28.90, 29)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    tag = EXCLUDED.tag,
    logo_url = EXCLUDED.logo_url,
    league_tier = EXCLUDED.league_tier,
    weekly_points = EXCLUDED.weekly_points,
    all_time_points = EXCLUDED.all_time_points,
    weekly_saved_co2_kg = EXCLUDED.weekly_saved_co2_kg,
    weekly_wasted_co2_kg = EXCLUDED.weekly_wasted_co2_kg,
    member_count = EXCLUDED.member_count;

SELECT setval('public.clans_id_seq', (SELECT MAX(id) FROM public.clans));

-- 3. Toplu Taşıma Durakları (Trabzon ve Kampüs 6 Durak)
INSERT INTO public.transit_stops (id, stop_code, nfc_uid, qr_payload, route_name, stop_name, latitude, longitude, avg_trip_km, points_reward, co2_saved_per_trip_kg)
VALUES
(1, 'TRB-KTU-01',  '04:A1:2B:9C:11:80:01', 'YESILADIM://TRANSIT/TRB-KTU-01?sig=9f8a7b',  'Kampüs Ring - Hat 1', 'KTÜ Atatürk Kültür Merkezi Durağı',       40.994210, 39.771540, 3.20,  3, 0.58),
(2, 'TRB-KTU-02',  '04:A1:2B:9C:11:80:02', 'YESILADIM://TRANSIT/TRB-KTU-02?sig=3c4d5e',  'Kampüs Ring - Hat 2', 'KTÜ Mühendislik / Milli Teknoloji Atölyesi',40.991850, 39.775120, 3.50,  3, 0.63),
(3, 'TRB-BLD-101', '04:B2:4C:8D:22:90:10', 'YESILADIM://TRANSIT/TRB-BLD-101?sig=7e6f5a', 'Belediye Otobüsü 101','KTÜ A Kapısı - Meydan Ana Durak',           40.998120, 39.768400, 6.80,  3, 1.22),
(4, 'TRB-BLD-104', '04:B2:4C:8D:22:90:14', 'YESILADIM://TRANSIT/TRB-BLD-104?sig=1a2b3c', 'Belediye Otobüsü 104','Kalkınma - Beşirli - Ayasofya Hattı',      40.996500, 39.765200, 11.40, 3, 2.05),
(5, 'TRB-BLD-501', '04:C3:5D:7E:33:A0:50', 'YESILADIM://TRANSIT/TRB-BLD-501?sig=8d9e0f', 'Belediye Ekspres 501','KTÜ Kanuni Kampüsü - Of Teknoloji Fakültesi',40.997800, 39.769100, 52.00, 3, 9.36),
(6, 'ANK-EGO-411', '04:D4:6E:6F:44:B0:41', 'YESILADIM://TRANSIT/ANK-EGO-411?sig=4f5a6b', 'EGO 411 & Başkentray','ODTÜ Metro - Kızılay Aktarma',             39.891200, 32.784500, 9.20,  3, 1.65)
ON CONFLICT (stop_code) DO UPDATE SET
    nfc_uid = EXCLUDED.nfc_uid,
    qr_payload = EXCLUDED.qr_payload,
    route_name = EXCLUDED.route_name,
    stop_name = EXCLUDED.stop_name,
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    avg_trip_km = EXCLUDED.avg_trip_km,
    points_reward = EXCLUDED.points_reward,
    co2_saved_per_trip_kg = EXCLUDED.co2_saved_per_trip_kg;

SELECT setval('public.transit_stops_id_seq', (SELECT MAX(id) FROM public.transit_stops));

-- 4. Mağaza Kozmetikleri (8 Ürün)
INSERT INTO public.shop_items (id, item_slug, category, name, price_gold, asset_preview, description)
VALUES
(1, 'frame_oxygen_glow',   'frame',  'Oksijen Neon Çerçevesi',     450,  'assets/shop/frame_oxygen.png',   'Profil fotoğrafının etrafında turkuaz yaprak efektleri döner.'),
(2, 'frame_ozone_purple',  'frame',  'Ozon Kalkanı Çerçevesi',     800,  'assets/shop/frame_ozone.png',    'Mor atmosferik kalkan parlaklığı.'),
(3, 'frame_biosfer_gold',  'frame',  'Sönmez Biyosfer Tacı',       1500, 'assets/shop/frame_biosfer.png',  'Sadece gerçek sıfır-atık efsanelerinin taşıyabileceği altın sarmaşık çerçeve.'),
(4, 'pet_pine_sprout',     'pet',    'Yürüyen Çam Fidanı (Pet)',   600,  'assets/shop/pet_pine.png',       'Sen adım attıkça büyüyen ve kozalak atan sevimli Karadeniz çamı.'),
(5, 'pet_robo_bee',        'pet',    'Biyo-Mekanik Arı (Pet)',     950,  'assets/shop/pet_bee.png',        'Profilinde uçuşarak polen ve oksijen puanı toplayan siber arı.'),
(6, 'pet_leaf_fox',        'pet',    'Orman Tilkisi (Pet)',        1200, 'assets/shop/pet_fox.png',        'Bisiklet sürdüğünde seninle birlikte koşan animasyonlu yoldaş.'),
(7, 'ava_cycling_pro',     'avatar', 'Aero Bisikletçi Avatarı',    350,  'assets/shop/ava_cyclist.png',    'Kasklı ve rüzgar gözlüklü özel bisikletçi karakteri.'),
(8, 'ava_ktu_mountaineer', 'avatar', 'Kaçkar Dağcısı Avatarı',     500,  'assets/shop/ava_climber.png',    'Kampüs yokuşlarını düz yol gibi çıkan efsanevi dağcı.')
ON CONFLICT (item_slug) DO UPDATE SET
    category = EXCLUDED.category,
    name = EXCLUDED.name,
    price_gold = EXCLUDED.price_gold,
    asset_preview = EXCLUDED.asset_preview,
    description = EXCLUDED.description;

SELECT setval('public.shop_items_id_seq', (SELECT MAX(id) FROM public.shop_items));

-- 5. Bildirim Şablonları (6 Şablon)
INSERT INTO public.notification_templates (id, trigger_code, title, body_template, action_button_text, severity)
VALUES
(1, 'RIVAL_PASSED_YOU', '🚨 Koltuğun Sallanıyor!', '{rival_name} az önce seni geçti ve sıralamada üstüne çıktı! Sen de anca yat... Kalk bir 500 adım at da yerini geri al!', 'Sıralamayı Gör', 'savage'),
(2, 'STEP_NUDGE_900',   '👟 5 Puan Çöpe mi Gitsin?', 'Şu an {current_mods} adımdasın! Sadece {remaining_steps} adım daha atarsan tam +5 puan kapacaksın. Koridorda iki tur atsan bitti bu iş!', 'Adımlarımı Tamamla', 'nudge'),
(3, 'INACTIVE_WALK',    '🕸️ Ayakların Örümcek Bağladı!', 'Tam {inactive_days} gündür doğru düzgün yürümüyorsun. Biraz yürü de ayağın açılsın, kasların paslandı be!', 'Yürüyüşe Başla', 'savage'),
(4, 'NO_TRANSIT_LATELY','🚌 Hayırdır, Araba mı Aldın???', 'Bu ara hiç otobüse binmiyorsun, hayırdır? Özel şoför mü tuttun yoksa gizli gizli taksiye mi biniyorsun? Utanç tablosu seni bekliyor!', 'QR/NFC Okut', 'savage'),
(5, 'CAR_DETECTED_LIVE','🚕 Yakalandın! Taksi mi O?', 'Hızın {speed_kmh} km/s ve otobüs kaydın yok! Bu yolu toplu taşımayla gitseydin {potential_co2_kg} kg CO2 tasarruf yapabilirdin aslında!!!', 'Utanç Tablosuna Bak', 'critical'),
(6, 'STREAK_DANGER',    '🔥 {streak_days} Günlük Serin Yanıyor!', 'Saat 21:00 oldu ve 6.000 adıma ulaşmana sadece {remaining_to_6k} adım kaldı! Seriyi bozarsan klanın yüzüne nasıl bakacaksın?', 'Seriyi Kurtar', 'urgent')
ON CONFLICT (trigger_code) DO UPDATE SET
    title = EXCLUDED.title,
    body_template = EXCLUDED.body_template,
    action_button_text = EXCLUDED.action_button_text,
    severity = EXCLUDED.severity;

SELECT setval('public.notification_templates_id_seq', (SELECT MAX(id) FROM public.notification_templates));

-- 6. Kullanıcılar (20 Referans Demo Kullanıcısı - Tümü is_demo = true ve Puan Eşiklerine Göre Doğrulanmış Tier)
INSERT INTO public.users (
    id, device_id, nickname, avatar_url, frame_slug, pet_slug, clan_id, league_tier,
    today_steps, weekly_points, all_time_points, gold_coins, streak_days, last_streak_date,
    weekly_saved_co2_kg, weekly_wasted_co2_kg, weekly_car_taxi_trips, weekly_car_taxi_km, is_demo, last_active_at
) VALUES
-- 1. Demo Kullanıcı: Sen (Efe) - 8.960 puan -> Tier 6 (Sönmez Biyosfer, min 1800)
('11111111-1111-1111-1111-111111111104', 'DEV-KTU-DEMO-USER-01', 'Sen (Efe)', 'assets/avatars/user_sen.png', 'frame_oxygen_glow', 'pet_pine_sprout', 1, 6,
 6666, 8960, 34500, 1450, 12, '2026-10-30', 12.40, 0.80, 1, 4.20, true, NOW() - INTERVAL '15 minutes'),

-- 2-4: Zirve Kullanıcılar (>=1800 -> Tier 6)
('11111111-1111-1111-1111-111111111101', 'DEV-KTU-USER-001', 'Zeynep Kaya', 'assets/avatars/ava_01.png', 'frame_biosfer_gold', 'pet_robo_bee', 1, 6,
 14250, 12480, 58900, 3200, 28, '2026-10-30', 21.80, 0.00, 0, 0.00, true, NOW() - INTERVAL '5 minutes'),
('11111111-1111-1111-1111-111111111102', 'DEV-KTU-USER-002', 'Burak Demir', 'assets/avatars/ava_02.png', 'frame_ozone_purple', 'pet_leaf_fox', 9, 6,
 11800, 11230, 49200, 2150, 19, '2026-10-30', 18.90, 0.00, 0, 0.00, true, NOW() - INTERVAL '1 hour'),
('11111111-1111-1111-1111-111111111103', 'DEV-KTU-USER-003', 'Elif Yılmaz', 'assets/avatars/ava_03.png', 'frame_ozone_purple', 'none', 2, 6,
 9420, 10540, 41800, 1890, 15, '2026-10-30', 16.50, 1.10, 1, 5.50, true, NOW() - INTERVAL '30 minutes'),

-- 5-9: Orta-Üst Sıralar (>=1800 -> Tier 6)
('11111111-1111-1111-1111-111111111105', 'DEV-KTU-USER-005', 'Mert Çelik', 'assets/avatars/ava_05.png', 'frame_oxygen_glow', 'none', 1, 6,
 7120, 7430, 28400, 980, 8, '2026-10-30', 10.20, 2.40, 2, 12.00, true, NOW() - INTERVAL '2 hours'),
('11111111-1111-1111-1111-111111111106', 'DEV-KTU-USER-006', 'Selin Şahin', 'assets/avatars/ava_06.png', 'none', 'none', 3, 6,
 6340, 6980, 24100, 820, 6, '2026-10-30', 9.80, 0.00, 0, 0.00, true, NOW() - INTERVAL '3 hours'),
('11111111-1111-1111-1111-111111111107', 'DEV-KTU-USER-007', 'Kerem Arslan', 'assets/avatars/ava_07.png', 'none', 'none', 1, 6,
 5890, 6320, 19500, 640, 4, '2026-10-29', 8.40, 3.80, 3, 19.00, true, NOW() - INTERVAL '4 hours'),
('11111111-1111-1111-1111-111111111108', 'DEV-KTU-USER-008', 'Ayşe Koç', 'assets/avatars/ava_08.png', 'none', 'none', 6, 6,
 6100, 5860, 17200, 510, 5, '2026-10-30', 7.90, 1.50, 1, 7.50, true, NOW() - INTERVAL '6 hours'),
('11111111-1111-1111-1111-111111111109', 'DEV-KTU-USER-009', 'Caner Aydın', 'assets/avatars/ava_09.png', 'none', 'none', 10, 6,
 4300, 5420, 15800, 430, 0, '2026-10-27', 6.50, 4.20, 4, 21.00, true, NOW() - INTERVAL '2 days'),

-- 10-15: Utanç Tablosu Kullanıcıları (Puan eşiklerine göre doğru tierler)
('11111111-1111-1111-1111-111111111110', 'DEV-SHAME-USER-010', 'Berkecan Taksi', 'assets/avatars/ava_shame_1.png', 'none', 'none', 1, 1,
 850, 120, 1450, 45, 0, NULL, 0.40, 38.60, 18, 193.00, true, NOW() - INTERVAL '1 day'),
('11111111-1111-1111-1111-111111111111', 'DEV-SHAME-USER-011', 'Pelinsu Yılmaz', 'assets/avatars/ava_shame_2.png', 'none', 'none', 4, 2,
 1120, 185, 2100, 90, 0, NULL, 0.90, 44.20, 22, 221.00, true, NOW() - INTERVAL '12 hours'),
('11111111-1111-1111-1111-111111111112', 'DEV-SHAME-USER-012', 'Taha Özkan', 'assets/avatars/ava_shame_3.png', 'none', 'none', 1, 2,
 1450, 240, 3200, 120, 0, '2026-10-20', 1.10, 29.80, 14, 149.00, true, NOW() - INTERVAL '3 days'),
('11111111-1111-1111-1111-111111111113', 'DEV-SHAME-USER-013', 'Cansu Erdem', 'assets/avatars/ava_shame_4.png', 'none', 'none', 1, 3,
 2300, 410, 4800, 210, 0, '2026-10-25', 2.00, 21.40, 11, 107.00, true, NOW() - INTERVAL '5 hours'),
('11111111-1111-1111-1111-111111111114', 'DEV-SHAME-USER-014', 'Oğuzhan Kılıç', 'assets/avatars/ava_shame_5.png', 'none', 'none', 11, 1,
 620, 95, 980, 30, 0, NULL, 0.20, 34.00, 16, 170.00, true, NOW() - INTERVAL '4 days'),
('11111111-1111-1111-1111-111111111115', 'DEV-SHAME-USER-015', 'Hakan Doğan', 'assets/avatars/ava_shame_6.png', 'none', 'none', 2, 3,
 3100, 620, 6400, 310, 1, '2026-10-29', 3.10, 18.20, 9, 91.00, true, NOW() - INTERVAL '1 day'),

-- 16-20: Farklı Lig ve Durumlarda 5 Ek Kullanıcı (Toplam 20 Kullanıcıyı Tamamlayan İdempotent Kayıtlar)
('11111111-1111-1111-1111-111111111116', 'DEV-KTU-USER-016', 'Deniz Yıldız', 'assets/avatars/ava_01.png', 'none', 'none', 7, 5,
 8200, 1420, 18200, 720, 7, '2026-10-30', 11.20, 0.00, 0, 0.00, true, NOW() - INTERVAL '40 minutes'),
('11111111-1111-1111-1111-111111111117', 'DEV-KTU-USER-017', 'Barış Aksoy', 'assets/avatars/ava_02.png', 'none', 'none', 8, 4,
 6500, 950, 12400, 480, 3, '2026-10-30', 8.60, 2.10, 1, 10.50, true, NOW() - INTERVAL '3 hours'),
('11111111-1111-1111-1111-111111111118', 'DEV-KTU-USER-018', 'Gizem Vural', 'assets/avatars/ava_03.png', 'none', 'none', 5, 3,
 4100, 520, 8900, 300, 2, '2026-10-29', 5.10, 0.00, 0, 0.00, true, NOW() - INTERVAL '1 day'),
('11111111-1111-1111-1111-111111111119', 'DEV-KTU-USER-019', 'Emre Bulut', 'assets/avatars/ava_05.png', 'none', 'none', 9, 2,
 2800, 290, 5100, 190, 1, '2026-10-28', 3.20, 4.80, 2, 24.00, true, NOW() - INTERVAL '2 days'),
('11111111-1111-1111-1111-111111111120', 'DEV-SHAME-USER-020', 'Sarp Kaya', 'assets/avatars/ava_shame_1.png', 'none', 'none', 3, 1,
 900, 80, 1100, 40, 0, NULL, 0.30, 24.50, 12, 122.50, true, NOW() - INTERVAL '1 day')
ON CONFLICT (id) DO UPDATE SET
    nickname = EXCLUDED.nickname,
    avatar_url = EXCLUDED.avatar_url,
    frame_slug = EXCLUDED.frame_slug,
    pet_slug = EXCLUDED.pet_slug,
    clan_id = EXCLUDED.clan_id,
    league_tier = EXCLUDED.league_tier,
    today_steps = EXCLUDED.today_steps,
    weekly_points = EXCLUDED.weekly_points,
    all_time_points = EXCLUDED.all_time_points,
    gold_coins = EXCLUDED.gold_coins,
    streak_days = EXCLUDED.streak_days,
    weekly_saved_co2_kg = EXCLUDED.weekly_saved_co2_kg,
    weekly_wasted_co2_kg = EXCLUDED.weekly_wasted_co2_kg,
    weekly_car_taxi_trips = EXCLUDED.weekly_car_taxi_trips,
    weekly_car_taxi_km = EXCLUDED.weekly_car_taxi_km,
    is_demo = EXCLUDED.is_demo;

-- 7. Demo Kullanıcıların Kuşandığı Eşyaları Envanterlerine Ekle
INSERT INTO public.user_inventory (user_id, item_slug)
VALUES
('11111111-1111-1111-1111-111111111104', 'frame_oxygen_glow'),
('11111111-1111-1111-1111-111111111104', 'pet_pine_sprout'),
('11111111-1111-1111-1111-111111111101', 'frame_biosfer_gold'),
('11111111-1111-1111-1111-111111111101', 'pet_robo_bee'),
('11111111-1111-1111-1111-111111111102', 'frame_ozone_purple'),
('11111111-1111-1111-1111-111111111102', 'pet_leaf_fox'),
('11111111-1111-1111-1111-111111111103', 'frame_ozone_purple'),
('11111111-1111-1111-1111-111111111105', 'frame_oxygen_glow')
ON CONFLICT (user_id, item_slug) DO NOTHING;

-- 8. Geçen Haftanın Şampiyonları (1 Kayıt - 2026-W43)
INSERT INTO public.weekly_champions (id, week_id, week_label, champion_user_id, champion_user_points, champion_clan_id, champion_clan_points, total_community_saved_co2_kg, announced_at)
VALUES
(1, '2026-W43', '19 - 25 Ekim 2026 Haftası', '11111111-1111-1111-1111-111111111101', 14850, 1, 138900, 1420.50, NOW() - INTERVAL '5 days')
ON CONFLICT (id) DO UPDATE SET
    week_id = EXCLUDED.week_id,
    week_label = EXCLUDED.week_label,
    champion_user_id = EXCLUDED.champion_user_id,
    champion_user_points = EXCLUDED.champion_user_points,
    champion_clan_id = EXCLUDED.champion_clan_id,
    champion_clan_points = EXCLUDED.champion_clan_points,
    total_community_saved_co2_kg = EXCLUDED.total_community_saved_co2_kg;

SELECT setval('public.weekly_champions_id_seq', (SELECT MAX(id) FROM public.weekly_champions));

-- 9. Örnek Aktivite Logları
INSERT INTO public.activities (
    user_id, activity_type, steps_count, distance_km, avg_speed_kmh, max_speed_kmh,
    accel_variance, transit_stop_id, points_earned, co2_delta_kg, verification_status, feedback_message, created_at
) VALUES
('11111111-1111-1111-1111-111111111104', 'walk', 6666, 5.12, 4.80, 6.20, 1.420, NULL, 30, 0.98, 'verified',
 'Harika gidiyorsun! Günlük adım barajını aştın ve streakini korudun.', NOW() - INTERVAL '25 minutes'),
('11111111-1111-1111-1111-111111111104', 'public_transit', 0, 6.80, 28.50, 54.00, 0.310, 3, 3, 1.22, 'verified',
 'Belediye Otobüsü 101 NFC doğrulandı! 1.22 kg CO2 salımını önledin.', NOW() - INTERVAL '4 hours'),
('11111111-1111-1111-1111-111111111104', 'bike', 0, 9.40, 18.20, 26.50, 0.890, NULL, 9, 1.80, 'verified',
 'Beşirli Sahil bisiklet sürüşün doğrulandı! +9 puan kazandın.', NOW() - INTERVAL '1 day'),
('11111111-1111-1111-1111-111111111110', 'bike', 0, 12.50, 58.40, 74.20, 0.080, NULL, 0, 0.00, 'rejected_speed_spoof',
 'HİLE TESPİT EDİLDİ! 74.2 km/s bisiklet hızı reddedildi.', NOW() - INTERVAL '6 hours'),
('11111111-1111-1111-1111-111111111110', 'car_taxi_penalty', 45, 8.50, 46.00, 82.00, 0.095, NULL, 0, -1.63, 'shame_logged',
 'Taksi kullanımı tespit edildi. Utanç tablosuna işlendi.', NOW() - INTERVAL '2 hours'),
('11111111-1111-1111-1111-111111111111', 'car_taxi_penalty', 20, 14.20, 52.00, 95.00, 0.070, NULL, 0, -2.72, 'shame_logged',
 'Özel araç kullanımı tespit edildi. 2.72 kg CO2 israfı kaydedildi.', NOW() - INTERVAL '3 hours')
ON CONFLICT DO NOTHING;

-- 10. Admin Canlı Bildirim Örnekleri
INSERT INTO public.admin_notifications_log (id, target_type, target_user_id, target_clan_id, template_code, title, message_body, severity, is_delivered, created_at)
VALUES
(1, 'user', '11111111-1111-1111-1111-111111111104', NULL, 'RIVAL_PASSED_YOU', '🚨 Koltuğun Sallanıyor!', 'Elif Yılmaz az önce seni geçti! Sen de anca yat... Kalk bir adım at da yerini geri al!', 'savage', true, NOW() - INTERVAL '12 minutes'),
(2, 'user', '11111111-1111-1111-1111-111111111110', 1, 'CAR_DETECTED_LIVE', '🚕 Yakalandın! Taksi mi O?', 'Hızın 64 km/s ve otobüs QR kaydın yok! Bu 8.5 km yolu 101 otobüsüyle gitseydin 1.63 kg CO2 tasarruf yapabilirdin!', 'critical', true, NOW() - INTERVAL '45 minutes'),
(3, 'clan', NULL, 2, 'CLAN_RIVAL_ALERT', '⚔️ KTÜ Kanuni Farkı Açıyor!', 'KTÜ OF Klanı uyuyor mu? KTÜ Kanuni bu hafta 125.430 puana ulaştı, acil yürüyüşe çıkın!', 'urgent', true, NOW() - INTERVAL '2 hours')
ON CONFLICT (id) DO UPDATE SET
    title = EXCLUDED.title,
    message_body = EXCLUDED.message_body,
    severity = EXCLUDED.severity;

SELECT setval('public.admin_notifications_log_id_seq', (SELECT MAX(id) FROM public.admin_notifications_log));



-- ============================================================================
-- 05_realtime.sql
-- Supabase Realtime Yayını Konfigürasyonu
-- Proje: Green_Project (fhaxxraibydsjikxacbb)
-- ============================================================================

DO $$
BEGIN
    -- supabase_realtime yayını mevcutsa dinlenecek tabloları ekle (idempotent)
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.admin_notifications_log;
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;

        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.clans;
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;

        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.weekly_champions;
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;

        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.users;
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;
    END IF;
END $$;
