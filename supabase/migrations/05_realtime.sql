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
