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
