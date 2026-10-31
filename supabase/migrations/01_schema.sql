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
