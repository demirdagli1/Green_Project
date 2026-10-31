# Supabase Backend Dağıtım Öncesi İnceleme Raporu

## 1. Statik İnceleme ve Yapılan Kritik Düzeltmeler
- **45 Dk Cooldown:** `rpc_record_transit` 15 dk hatası düzeltildi; QR ve NFC kanonik kod üzerinden 45 dk ortak cooldowna bağlandı.
- **Puan ve CO₂ Kapıları:** İstemciden gelen parametreler yerine sunucu hesabı getirildi (adım/1000×5 puan, bisiklet FLOOR(km) & km×0.19 kg CO₂, 6k streak kuralı).
- **Hız ve İsraf Denetimi:** Bisiklette max≥50 veya ort≥35 km/s ret; ort>25 km/s ve varyans<0.12 araba cezası (km×0.192 kg CO₂); transit son 45 dk araç muafiyeti sağlandı.
- **Eşzamanlılık & Idempotency:** `processed_events` öncesi `pg_advisory_xact_lock` ile paralel mükerrer çağrılarda çift ödül/ceza riski sıfırlandı.
- **RLS & Yetki Sıkılaştırma:** `users` REST UPDATE yalnız `nickname, bio (max 160), photo_path, last_active_at` ile sınırlandı; envanter/klan/altın yetkisiz PATCH engellendi.
- **Admin & Edge Function Güvenliği:** `PUBLIC/anon` EXECUTE hakları kaldırıldı; Edge Function'lara zorunlu JWT ve `server_admins` kontrolü eklendi (FCM değil Realtime kuyruğu).
- **Haftalık Reset Idempotency:** `weekly_champions` tablosuna `week_id UNIQUE` eklendi; reset haftada tek sefere kilitlendi; günlük adım/streak korundu.

## 2. Canlı Durum ve Ayrım
- **Canlıda Doğrulanan:** Proje `fhaxxraibydsjikxacbb` Frankfurt canlı; Anonymous Auth aktif ve HTTP 200/is_anonymous=true olarak kök doğrulamalıdır.
- **Statik İncelenen (Canlıya Henüz Uygulanmayan):** `supabase/` altındaki 1.809 satırlık konsolide `full_deployment.sql` ve 10 bloklu assertion paketi `verification.sql`.

## 3. Root Dağıtım ve Doğrulama Talimatı
1. `supabase/full_deployment.sql` dosyasını Supabase SQL Editor veya root MCP `execute_sql` ile tek seferde çalıştırın.
2. `supabase/verification.sql` test dosyasını çalıştırın; 10 test bloğunun tamamında `BAŞARILI ✅` döndüğünü teyit edin.
3. Flutter ve istemci kodlarına dokunulmamış; istemci RPC sözleşmesi `SUPABASE_HAZIRLIK.md` ile tam uyumlu hale getirilmiştir.
