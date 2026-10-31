# Supabase Güvenlik İncelemesi Düzeltme Raporu

1. **Private Alan Sızıntısı Giderildi:** `users` tablosundan `gold_coins`, `device_id`, `last_streak_date` ve ham utanç kolonları (`weekly_wasted_co2_kg`, `weekly_car_taxi_*`) `anon` ve `authenticated` rollerinden tamamen kaldırıldı.
2. **Dar Sütun Seviyesi Projeksiyon:** `users` tablosuna yalnızca güvenli genel alanlar (ad, avatar, bio, lig, puan, tasarruf, streak) için SELECT verildi; `SELECT *` veya `SELECT gold_coins` doğrudan REST ile çağrılamaz (`insufficient_privilege`).
3. **Dar Sahiplikli Özel Durum Erişimi:** Altın bakiyesi, donanım ID ve envanter yalnızca kullanıcının kendi oturumuna özel `rpc_get_my_profile()` RPC'si üzerinden döner; başka hesaptan okunamaz.
4. **Maskeli Utanç Görünümleri:** Utanç ölçümleri doğrudan tablodan değil, isimlerin maskelendiği (`Ahm***`) güvenli `v_clan_shame_board` ve `v_global_shame_board` projeksiyonlarıyla sınırlandı.
5. **En Az Yetki İlkesi (Least Privilege):** Tablolarda varsayılan haklar sıfırlandı; `transit_stops` tablosundan `nfc_uid` ve `qr_payload` gizlendi; `notification_templates` yalnız yöneticilere açıldı.
6. **Yönetici Fonksiyon İzolasyonu:** `rpc_admin_trigger_weekly_reset` ve `rpc_admin_send_notification` sıradan kullanıcılardan geri alındı; yalnızca `service_role` (Edge Function) yetkisine bağlandı.
7. **Çapraz Kimlik Doğrulama Assertion'ı:** `verification.sql` Test 4'e iki farklı auth kimliğiyle Kullanıcı A'nın Kullanıcı B'ye ait `gold_coins`, `device_id` ve `SELECT *` okuyamayacağını kanıtlayan testler eklendi.
8. **İstemci Sözleşmesi & Bütünlük:** `SUPABASE_HAZIRLIK.md` API View Okuma Sözleşmesi ile güncellendi; `lib/` istemci kodlarına dokunulmadı; `full_deployment.sql` parçalarla 1-e-1 eşitlendi.
9. **Dağıtım Durumu:** DROP komutu ve veri kaybı yoktur; root MCP `apply_migration` ile canlıya tekrar uygulamaya hazırdır.
