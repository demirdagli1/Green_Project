# Supabase Canlı Backend Hazırlığı ve İstemci Sözleşmesi

**Proje:** Green_Project (`fhaxxraibydsjikxacbb`)  
**Bölge:** Frankfurt (eu-central-1)  
**Sunucu URL:** `https://fhaxxraibydsjikxacbb.supabase.co`  
**İstemci Anahtarı:** `.env.supabase.json` dosyasında `SUPABASE_PUBLISHABLE_KEY` (APK'da asla `service_role` kullanılmaz).

---

## 1. Hazırlanan Dosyalar ve Mimari

Tüm backend bileşenleri `supabase/` altında, bağımsız ve idempotent olarak hazırlanmıştır:

| Dosya Yolu | Açıklama |
|---|---|
| `supabase/migrations/01_schema.sql` | 13 tablo, CHECK kısıtları, foreign keyler, B-Tree indeksler ve güvenli görünümler. |
| `supabase/migrations/02_security_rls.sql` | En az yetki (least privilege), RLS, sahiplik izolasyonu, kolon seviyesi yetkilendirme (`device_id`/`gold_coins` kamuya kapalı). |
| `supabase/migrations/03_functions_and_rpc.sql` | Atomik RPC'ler, lig kademesi tetikleyicileri, cooldown kontrolü, mağaza alım/kuşanma; admin RPC'leri service_role iznine bağlı. |
| `supabase/migrations/04_seed_data.sql` | 12 lig, 11 klan (düzeltilmiş lig kademeleriyle), 20 demo kullanıcı (`is_demo=true`), 6 durak, 8 mağaza kozmetiği vb. |
| `supabase/migrations/05_realtime.sql` | `supabase_realtime` yayınına canlı dinlenecek tabloların (`admin_notifications_log`, `clans`, `users`, `weekly_champions`) eklenmesi. |
| `supabase/full_deployment.sql` | 01-05 arası tüm adımların tek seferde hatasız uygulanmasını sağlayan konsolide dağıtım SQL'i. |
| `supabase/verification.sql` | İki kimlik arası gold/device_id okunamama assertion'ı, tablo sayıları, lig eşikleri, RLS izolasyonu ve cooldown kurallarını test eden doğrulama paketi. |
| `supabase/functions/weekly-reset/index.ts` | Pazar gecesi sıfırlamasını tetikleyen güvenli Edge Function entrypoint'i. |
| `supabase/functions/send-push/index.ts` | GM/Admin canlı bildirim gönderme Edge Function entrypoint'i. |

---

## 2. Kimlik Doğrulama (Anonymous Auth) Mimarisi

- **Sessiz Oturum:** Kullanıcıdan e-posta, şifre veya telefon istenmez. Uygulama açılışında:
  ```dart
  await supabase.auth.signInAnonymously();
  final String userId = supabase.auth.currentUser!.id;
  ```
- **Yetki Dayanağı:** Cihazın yerel UUID'si (`device_id`) sadece donanım referansıdır; veritabanında tüm yetki Postgres JWT'deki `auth.uid()` üzerinden yürütülür.
- **Anon Provider Ayarı:** Supabase Dashboard -> **Authentication** -> **Providers** -> **Anonymous** seçeneği `Enabled` olmalıdır.

---

## 3. İstemci Sözleşmesi (AppStore ve Yerel Durum Eşlemesi)

### 3.1. İlk Senkronizasyon (Legacy Local First-Sync)
Uygulama ilk kez bağlandığında yerel `AppStore` durumundaki profil ve puanlar kontrollü taşınır:
```sql
SELECT public.rpc_sync_initial_profile(
    p_device_id       => 'DEV-DEVICE-UUID',
    p_nickname        => 'Efe',
    p_clan_id         => 1,
    p_avatar_url      => 'assets/avatars/user_sen.png',
    p_bio             => 'KTÜ Kampüs Yürüyüşçüsü',
    p_legacy_steps    => 6666,
    p_legacy_points   => 8960,
    p_legacy_gold     => 1450,
    p_legacy_co2      => 12.40
);
```
- **Sunucu Tek Gerçek Kaynaktır:** Kullanıcı önceden kayıtlıysa sunucudaki profil döner; yerel eski snapshot sunucu verisinin üstüne yazılmaz.
- **Hile Sınırı:** İlk senkronizasyonda yerel puan/altın için makul üst tavanlar (`v_safe_points`, `v_safe_gold`) uygulanır.

### 3.2. Atomik Olaylar ve İdempotency (Pending Queue & Offline Retry)
İstemci her hareket eylemi için istemci tarafında bir `event_id` (UUIDv4) üretir:

| Eylem | RPC Adı | Parametreler | İdempotent Sonuç |
|---|---|---|---|
| Adım Ekleme | `rpc_record_steps` | `p_event_id, p_step_count, p_distance_km` | Aynı `event_id` gelirse puan/adım tek kez yazılır; ikinci çağrı `duplicate: true` döner. Sunucu 1.000 adım = 5 puan ve 6k streak kuralını kendisi işletir. |
| Durak Tarama | `rpc_record_transit` | `p_event_id, p_stop_code, p_verification_method` | 45 dakika ortak cooldown kontrolü (QR ve NFC ortak kanonik durak) + sunucu puan/CO2 ekleme. |
| Bisiklet Sürüşü | `rpc_record_bike` | `p_event_id, p_distance_km, p_avg_speed_kmh, p_max_speed_kmh, p_accel_variance` | Hız hilesinde (≥50 veya ≥35 km/s) ret; düşük varyansta (<0.12) araba şüphesi cezası; geçerliyse FLOOR(km) puan ve km×0.19 kg CO2 tasarrufu. |
| Taksi / Araba İsrafı | `rpc_record_vehicle_penalty` | `p_event_id, p_distance_km, p_avg_speed_kmh` | Son 45 dk içinde transit kaydı varsa muaf; yoksa km×0.192 kg CO2 utanç sicili ve sayaç artışı. |
| Profil Güncelleme | `rpc_update_profile` | `p_nickname, p_bio, p_photo_path` | Sahiplik doğrulamalı ve bio maksimum 160 karakter kısıtlı profil güncellemesi. |
| Kozmetik Alma | `rpc_buy_shop_item` | `p_item_slug` | Bakiye kontrolü, altın düşüşü ve envantere yazma tek atomik işlemde. |
| Kozmetik Kuşanma | `rpc_equip_shop_item` | `p_item_slug` | Envanter sahiplik doğrulaması ve profil slotu güncellemesi. |
| Klana Katılma | `rpc_join_clan` | `p_clan_id` | Eski klan üye sayısı düşülür, yeni klan üye sayısı artırılır. |

### 3.3. API Görünüm Okuma Sözleşmesi (View Read Contract)

İstemci ajanı için güvenli veri okuma kuralları:

1. **`users` Tablosuna `SELECT *` veya Private Kolon Sorgusu Yapılamaz:**
   - `users` tablosunda `gold_coins`, `device_id`, `last_streak_date`, `weekly_wasted_co2_kg`, `weekly_car_taxi_trips`, `weekly_car_taxi_km` kolonları anon ve authenticated rollerine kapalıdır.
   - Doğrudan `supabase.from('users').select('*')` veya `.select('gold_coins')` çağrısı Postgres düzeyinde `insufficient_privilege` hatası fırlatır.

2. **Kamusal Liderlik Tablosu Okuma:**
   - Görünüm: `v_leaderboard_users`
   - Sorgu: `supabase.from('v_leaderboard_users').select().order('weekly_points', ascending: false).limit(50)`
   - Sağlanan Kolonlar: `user_id, nickname, avatar_url, frame_slug, pet_slug, clan_id, clan_name, clan_tag, league_tier, today_steps, weekly_points, all_time_points, weekly_saved_co2_kg, streak_days, is_demo, last_active_at, rank`.

3. **Klan Sıralaması Okuma:**
   - Görünüm: `v_clan_leaderboard` (veya `clans` tablosu)
   - Kolonlar: `clan_id, clan_name, clan_tag, logo_url, league_tier, weekly_points, all_time_points, weekly_saved_co2_kg, weekly_wasted_co2_kg, member_count, rank`.

4. **Maskeli Utanç Tabloları:**
   - Klan İçi: `v_clan_shame_board` (`clan_id, clan_name, user_id, masked_name, avatar_url, weekly_car_taxi_trips, weekly_car_taxi_km, weekly_wasted_co2_kg, shame_rank`). İsimler `Ahm***` maskelidir.
   - Genel: `v_global_shame_board` (`user_id, masked_name, avatar_url, clan_name, weekly_car_taxi_trips, weekly_car_taxi_km, weekly_wasted_co2_kg, global_shame_rank`).

5. **Kullanıcının Kendi Özel Durumunu (Altın, Cihaz ID, Envanter) Okuması:**
   - İstemci kendi bakiyesini doğrudan `users` tablosundan değil, dar sahiplikli RPC ile alır:
     ```dart
     final res = await supabase.rpc('rpc_get_my_profile');
     // res['user']['gold_coins'] -> Oturum sahibinin gerçek bakiyesi
     // res['inventory'] -> ['frame_oxygen_glow', ...]
     ```

6. **Toplu Taşıma Durakları:**
   - `supabase.from('transit_stops').select()` sorgusu güvenli coğrafi durak bilgilerini döner. `nfc_uid` ve `qr_payload` kolonları kamuya kapalıdır; doğrulama `rpc_record_transit` üzerinden yürütülür.

7. **Yönetici İşlemleri:**
   - `rpc_admin_trigger_weekly_reset` ve `rpc_admin_send_notification` sıradan kullanıcılara kapatılmıştır; Edge Function (`weekly-reset`, `send-push`) üzerinden `service_role` ile tetiklenir.

### 3.4. Gerçek Zamanlı (Realtime) Abonelikler
```dart
// 1. Canlı Yönetici & Dürtücü Bildirimler
supabase.channel('public:admin_notifications_log')
  .onPostgresChanges(
    event: PostgresChangeEvent.insert,
    schema: 'public',
    table: 'admin_notifications_log',
    callback: (payload) => onNotificationReceived(payload.newRecord),
  )
  .subscribe();

// 2. Canlı Klan Puan Değişimleri
supabase.channel('public:clans')
  .onPostgresChanges(
    event: PostgresChangeEvent.update,
    schema: 'public',
    table: 'clans',
    callback: (payload) => onClanUpdated(payload.newRecord),
  )
  .subscribe();

// 3. Kullanıcı Kendi Satırını Dinler (RLS filtreli)
supabase.channel('public:users')
  .onPostgresChanges(
    event: PostgresChangeEvent.all,
    schema: 'public',
    table: 'users',
    callback: (payload) => onMyUserUpdated(payload.newRecord),
  )
  .subscribe();
```

---

## 4. Güvenlik ve Gizlilik Garantileri

1. **`gold_coins` ve `device_id` Tam İzolasyonu:** Kamusal tablodan veya görünümlerden diğer kullanıcıların altın bakiyesi ya da donanım ID'si çekilemez. Yalnızca oturum sahibi `rpc_get_my_profile()` ile okuyabilir.
2. **Utanç Tablosu Maskelemesi:** Ham utanç metrikleri `users` tablosundan kamuya kapatılmış; yalnızca `v_clan_shame_board` ve `v_global_shame_board` üzerinden maskeli takma adlarla sunulur.
3. **Doğrudan REST PATCH Koruması:** `users` tablosuna authenticated kullanıcıların doğrudan `gold_coins`, `weekly_points`, `all_time_points` güncellemesi yapması Postgres sütun seviyesinde (`REVOKE UPDATE`) engellenmiştir.
4. **En Az Yetki (Least Privilege):** Tüm tablolar için default grantler sıfırlanmış, admin RPC'leri authenticated rolünden arındırılmıştır.

---

## 5. Root Deployment ve Doğrulama Adımları

1. **Dağıtımın Uygulanması:**
   - `supabase/full_deployment.sql` dosyasının içeriği Supabase Dashboard SQL Editöründe veya root MCP ile çalıştırılır.
2. **Doğrulama Testlerinin Koşulması:**
   - `supabase/verification.sql` çalıştırılır. 10 test bloğunun tamamında (özellikle Test 4'teki gold/device_id okunamama assertion'larında) `BAŞARILI ✅` görüldüğü teyit edilir.
3. **Anonymous Provider Kontrolü:**
   - Dashboard'da Anonymous Auth'un açık olduğu doğrulanır.
