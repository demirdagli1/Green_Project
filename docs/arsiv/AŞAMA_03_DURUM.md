# ROOT_07_HAZIR: supabase/migrations/07_delivery.sql

# Aşama 03 — Revizyon 03 Durum ve Takip Raporu

**Tarih:** 31 Ekim 2026  
**Durum:** `ROOT_07_HAZIR` (`06_revizyon_03.sql` canlıya uygulandı; ana teslimat için minimal ve güvenli `supabase/migrations/07_delivery.sql` paketi hazırlandı; GM paneli port 8787 ve yetki kontrolleri tamamlandı; iki oturumlu canlı cloud testleri 100% başarılı)  
**Teslim Edilen APK:** `releases/YeSilAdim-debug.apk` (173.965.301 bayt)  
**SHA-256 Özeti:** `1f09907ec13f3f31ba3ddc58721a7eb331546cef309e658c908290142827d19b`  

---

## 1. ROOT DAĞITIMI GEREKTİREN DOSYALAR (`ROOT_07_HAZIR`)

Kullanıcının değişen son önceliği doğrultusunda, otomatik otobüs motoru bağımsız bir çalışma ağacına (`.worktrees/automatic-bus`) devredilmiş olup ana teslimatı bloke etmemektedir. Ana projenin veri bütünlüğünü ve bulut uyumunu garanti altına almak üzere hazırlanan küçük sunucu paketi:

* **Yeni Artımlı Teslimat Dağıtım Dosyası:** `supabase/migrations/07_delivery.sql`
* **Güvenli Rollback Doğrulama Paketi:** `supabase/verification_rev03.sql` (Açık `BEGIN ... ROLLBACK` içinde canlı mutasyon bırakmadan utanç panoları, mesajlaşma, kota, dormant otobüs yanıtı ve GM audit trail yetkilendirmesini test eder).

### `07_delivery.sql` İçeriği:
1. **Utanç Panoları `security_invoker = true` Sütun İzinleri:**
   `v_clan_shame_board` ve `v_global_shame_board` görünümlerinin çağıran roller tarafından hatasız okunabilmesi için `public.users` üzerindeki `clan_role`, `weekly_car_taxi_trips`, `weekly_car_taxi_km`, `weekly_wasted_co2_kg` sütunlarına `anon` ve `authenticated` rolleri için `GRANT SELECT` tanımlandı.
2. **`rpc_record_transit` FOR UPDATE Kilidi ve 45 dk Cooldown:**
   - Cooldown kontrollerinden önce `SELECT * INTO v_user FROM public.users WHERE id = v_user_id FOR UPDATE` satır kilidi eklendi.
   - 45 dakikalık cooldown denetimi hem durak kodunu hem de `'AUTO_BUS_TRIP'` anahtarını kapsar; ters sırada binişlerde mükerrer ödül oluşması engellenmiştir.
   - `processed_events` tablosuna zorunlu `event_type = 'transit_scan'` ile yazılır.
3. **`rpc_record_bus_trip` Dormant Fonksiyon Koruması:**
   Otomatik otobüs motoru diğer AGY tarafından ayrı çalışma alanında tamamlanana kadar, canlı veritabanında `processed_events.event_type` NOT NULL kısıt ihlallerini veya yanlış puan/CO₂ oluşmasını engellemek üzere bu RPC güvenli `ok: false, dormant: true, points_delta: 0` durumu döner.

---

## 2. EVRENSEL GM PANELİ (PORT 8787) VE YETKİ SORUNU ÇÖZÜMÜ

Kullanıcının panelde karşılaştığı `permission denied` sorunu kökünden çözüldü:

1. **Varsayılan Anon Erişiminin Kapatılması:**
   `tools/universal_gm/index.html` içinde varsayılan `ANON_KEY` ile açıldığında GM butonlarının aktif görünmesi engellendi; tüm işlem düğmeleri (`.gm-action-btn`) yetkili oturum doğrulanana kadar varsayılan olarak devre dışı (`disabled = true`) bırakıldı.
2. **Tek Seferlik Güvenli Oturum İçe Aktarımı ve Token Refresh:**
   - Root tarafından üretilmiş `.gm-private/gm_admin_session.private.json` oturum dosyası dosya seçici ile panele aktarılır.
   - Panel `rpc_get_my_profile` çağrısıyla `is_admin === true` teyidi alır. Yetkisiz hesaplar için açık, yanıltıcı olmayan hata bildirimi yapılır.
   - Token süresi dolduğunda `auth/v1/token?grant_type=refresh_token` uç noktası üzerinden kalıcı oturum otomatik yenilenir.
3. **Port 8787 Desteği:**
   Kullanıcının port 8080 üzerinde `llama-server` çalıştırması nedeniyle GM web konsolu port 8787 üzerinde başarıyla yayına alındı (HTTP 200).
4. **XSS Koruması:**
   Kullanıcı takma adları, klan adları ve hata iletileri `escapeHtml` ile sanitize edildi; localStorage ve DOM üzerindeki admin oturumu korundu.

---

## 3. İKİ GERÇEK ANONİM OTURUM VE CLOUD DOĞRULAMA KANITI

`tools/test_two_sessions.dart` aracı canlı Supabase (`fhaxxraibydsjikxacbb`) üzerinde çalıştırılmış ve tüm adımlar hatasız geçmiştir:

* **404 Kontrolü:** Tüm uç noktalar HTTP 404'e karşı assert edildi.
* **RLS İzolasyonu:** Oturum B'nin, Oturum A'nın özel envanter verilerine ve admin audit kayıtlarına erişemediği (0 satır) doğrulandı.
* **Yetkisiz GM Reddi:** Standart oturumun GM RPC çağrısı sunucu tarafından 403 ile reddedildi (`server_admins` koruması aktif).
* **Parametre Sözleşmeleri:** Negatif otobüs mesafesi ve kendine utanç mesajı sunucu tarafından reddedildi.
* **Gerçek Çapraz Puan Mutasyonu ve Realtime:**
  - Oturum A adım aktivitesi işledi (+5 puan).
  - Oturum B, kamuya açık `v_leaderboard_users` görünümünden Oturum A'nın güncel puanını (5) anında okudu.
  - Realtime WebSocket kanalına (`realtime:public`) başarıyla bağlanılarak `phx_reply` teyidi alındı.
  - Süreç kod 0 ile temiz bir şekilde kapandı.

---

## 4. İSTEMCİ VE ARAYÜZ DÜZENLEMELERİ

1. **Utanç Mesajı Altın Güvencesi:**
   `lib/screens/leaderboard/leaderboard_screen.dart`: Peşin altın kesintisi kaldırıldı; 10 altın düşümü yalnızca sunucudan `res['ok'] == true` teyidi alındıktan sonra işlenir.
2. **Kısa Otobüs ve Puan Uzlaştırması:**
   `lib/services/app_store.dart`: Negatif puanlarda `allTimePoints` korunur.
3. **Klan Hiyerarşisi ve Klansız Kullanıcılar:**
   Sunucudan gelen `clan_role` hiyerarşisi istemciye bağlandı (`Lider`, `Kıdemli`, `Üye`). Klansız kullanıcıların rastgele `Clan 1`'e atanması engellendi (`clanId: ''`).
4. **Mükerrer Bottom Nav Sekmesi:**
   QR/NFC sayfasının içindeki mükerrer TabBar kaldırıldı, sadeleştirildi.
5. **Kuşanılan Pet Gösterimi:**
   Profil ekranında `bit-bee.png` ve `auro-fairy.png` kuşanıldığında profil fotoğrafının hemen sağında gösterilmektedir.
6. **Outbox İyileştirmesi:**
   Dormant otobüs yanıtları outbox kuyruğunu tıkamayacak şekilde `itemDone = true` olarak işaretlenir.

---

## 5. TEST, ANALİZ VE DERLEME ÖZETİ

* **Statik Kod Analizi:**  
  `dart analyze` ➔ **0 issue (0 hata, 0 uyarı)**
* **Birim ve Entegrasyon Testleri:**  
  `flutter test --no-pub --concurrency=1` ➔ **132 / 132 test BAŞARILI!**
* **Çevrimdışı Android APK Derlemesi:**  
  Tek worker / JDK 17 ile **20 saniyede tamamlandı**.  
  - Dosya: `releases/YeSilAdim-debug.apk` (173.965.301 bayt)  
  - SHA-256: `1f09907ec13f3f31ba3ddc58721a7eb331546cef309e658c908290142827d19b`  
  - Doğrulama: `sha256sum -c releases/YeSilAdim-debug.apk.sha256` ➔ **OK**
