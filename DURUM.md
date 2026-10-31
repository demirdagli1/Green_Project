# Devam noktası — 31 Ekim 2026

Bu dosya güncel kayıttır. Eski raporlar `docs/arsiv/` içindedir; hepsini tekrar okumak gerekmez.

## Kullanıcıyla çalışma
- Codex yönetir; ürün/test/SQL kodunu AGY Gemini 3.8 Flash High yazar. Tokenı koru, kısa ve sade konuş. Git yerel; **push yok**. Ayrıntılı kurallar: [AGENT_YONETIM.md](AGENT_YONETIM.md).
- İndirme yok; kurulu Flutter/JDK/SDK ve çevrimdışı önbellekler kullanılır. Tek ağır test/derleme, Gradle tek worker/2 GB heap.
- Kullanıcının `Düzenlemeler.txt` değişiklikleri korunuyor, yönetici commitine katılmadı.
- Root bağlı cihazda `adb install -r releases/YeSilAdim-debug.apk` çalıştırdı: Success. Uygulama verileri silinmedi; MainActivity açma komutu gönderildi. Elle test kullanıcıya ait.

## Son tamamlanan teslim paketi (GM 600k Adım/Puan Senkronizasyonu & Ortak Utanç Panosu)
- **Hata 1 (GM 600k Adım Puanı & Muhasebe) Tamamen Çözüldü:**
  - GM panelinden `set_steps` ve `add_steps` çağrıldığında yalnızca `today_steps` artıp puanın sıfır kalma hatası düzeltildi.
  - `public.activities` üzerindeki günlük `walk` etkinlikleri muhasebesi esas alındı: `(new_steps / 1000 * 5) - already_awarded_from_walk`.
  - Canlıda daha önce 600k adım verilip 0 puan almış bozuk kullanıcılar, GM'in aynı değere `set_steps(600000)` çağırmasıyla eksiksiz **+3.000 puan** olarak onarılır.
  - İdempotency ve tekrar çağrılarda `points_delta = 0` dönerek asla mükerrer/çifte puan üretmez.
  - `add_steps` için 100.000 üst sınırı aşılırsa (`count > 100000`), miktar sessizce kırpılmadan net Türkçe hata mesajı döner. `set_steps` için 1.000.000 sınırı (600.000 dahil) geçerlidir.
  - Adım artışıyla haftalık puan, all-time puan ve klan toplamı atomik güncellenir; 6.000 adım streak kuralı tetiklenir.
- **Hata 2 (Cihazlar Arası Farklı Utanç Listesi & Mesaj Gönderilememe) Çözüldü:**
  - Utanç tablosu artık puan top50'si yerine doğrudan `v_global_shame_board` görünümünden çekilen bağımsız ortak sunucu snapshot'ına (`serverShameUsers`) bağlandı.
  - `SupabaseService.fetchServerShameBoard(store)` bağımsız helper haline getirildi; klan liderliği veya diğer sorguların başarısızlığından etkilenmez.
  - `isServerShameLoaded = true` bayrağı ile sunucu snapshot'ı boş olsa dahi (0 israfçı) demo listesine geri düşüş (fallback) engellendi.
  - Cihazın kendi kullanıcısı (`me`) sunucu sırasının üstüne keyfi eklenmez (`no me-override`); kullanıcı kendi sırasını sunucu snapshot'ından alır.
  - Realtime `users` tablosu değişiklikleri 300ms debounce ile `fetchServerShameBoard`'u tetikler (yankı/reentrant fırtınası önlendi).
  - Demo hedeflere mesaj gönderilemez, altın düşülmez; çevrimdışıyken sahte "iletildi" mesajı verilmez.
- **Canlı Sunucu Doğrulaması:**
  - Migration 11: `green_project_gm_steps_points_and_shame_fix` root tarafından preflight BEGIN/ROLLBACK testleri (%100 PASS) sonrası canlı veritabanına uygulandı.

## Kanıtlar, Testler ve APK
- **Dart Analizi:** `dart analyze` ➔ **No issues found!** (0 hata, 0 uyarı).
- **Otomatik Testler:** Çevrimdışı, `--no-pub --concurrency=1` ile **136/136 test BAŞARIYLA GEÇTİ** (`All tests passed!`). GM 600k onarım, sınır kontrolleri, utanç boş snapshot ve bağımsız shame fetch testleri eklendi.
- **Gradle Derlemesi:** `android/local.properties` Türkçe karakter yolu `Masa\u00fcst\u00fc` Java unicode escape korunarak `./gradlew assembleDebug --offline --no-daemon --max-workers=1` ile **16 saniyede BUILD SUCCESSFUL** tamamlandı.
- **APK Dosyası:** [releases/YeSilAdim-debug.apk](releases/YeSilAdim-debug.apk), **173.963.533 bayt**.
- **SHA-256:** `c69f5be1f4c43883b3c792e9c46c734729d31647c57f8f9366d99d9597c12683`.
- **Doğrulama:** `sha256sum -c releases/YeSilAdim-debug.apk.sha256` ➔ **OK**.

## Canlı sunucu: son kesin durum
- Proje `fhaxxraibydsjikxacbb`, Green_Project, eu-central-1; 0 $/ay kullanıcı tarafından onaylandı. Anonymous Auth çalışıyor. Başka projelere dokunulmadı.
- Uygulanan migration'lar: `green_project_initial_schema_safe`, `green_project_revision_03`, `green_project_delivery_fixes`, `green_project_transit_input_validation`, `green_project_transit_schema_fix`, `green_project_gm_alert_notification`.
- 08 sürümündeki hatalı alan adları 09 ile düzeltildi. 09 önce `supabase/preflight_delivery.sql` ile açık BEGIN/ROLLBACK içinde **başarıyla** test edildi, ardından uygulandı. Sonrasında `supabase/verification_rev08.sql` de **başarıyla** çalıştı. Testler kalıcı kullanıcı mutasyonu bırakmadı.
- Son doğrulama; boş/yanlış/wildcard durak kodları, 44:59 ret / 45:00 kabul, gerçek seed URI/NFC eşleşmeleri ve yetkili GM/audit yollarını kapsar. Testteki küsurat beklentisi DB hassasiyetine uyarlandı; uydurma durak kodları gerçek seed verileriyle değiştirildi.
- Son güvenlik danışmanı: 0 ERROR, 14 WARN. Definer RPC/anonim politika ve parola ayarı uyarıları mevcut; bütün uyarılar giderildi denmemeli.
- Dağıtılmış migration'ları tekrar yazıp uygulama. `supabase/drafts/07_revizyon_03_fix.sql` eski, **uygulanmamış taslaktır**; migration dizininden ayrıldı.
- Migration 10 root tarafından açık BEGIN/ROLLBACK preflight ile başarıyla doğrulandı ve `green_project_gm_alert_notification` olarak uygulandı. Yetkisiz ret, tek bildirim/tek audit ve mevcut adım/altın/seri/puan/kota yolları doğrulandı. Gerçek telefon bildirimi/ses/titreşim henüz kullanıcı tarafından test edilmedi.

## GM paneli
- Adres: http://127.0.0.1:8787 . 8080 kullanıcının başka servisine ayrıldı.
- Giriş için proje kökündeki **GM-Yonetici-Oturumu.private.json** dosyasını panelde içe aktar. Görünür kopya kullanıcı bulabilsin diye oluşturuldu. Asıl dosya `.gm-private/gm_admin_session.private.json`.
- Dosyalar 600, özel dizin 700; Git'e kapalı, web kökü dışında. İçeriklerini çıktı/rapor/commitlere koyma. İlgili oturumun profili ve `server_admins` yetkisi root tarafından oluşturuldu.
- Girişsiz işlem düğmeleri kapalı; oturum yenileme eklendi. Kullanıcı dosyayı bulmakta zorlandı; yol verildi. Tarayıcıdaki son kullanıcı denemesi ayrıca onaylanmadı.
- Yeniden başlatma komutu: `python3 -m http.server 8787 --bind 127.0.0.1 --directory tools/universal_gm`.

## Otobüs: ayrı taslak, ana teslimi bekletmiyor
- Kullanıcı otobüsün yetişmezse eksik bırakılmasını açıkça kabul etti. Ana sunucuda otomatik otobüs RPC'si geliştirme yanıtı verir, ödül/ceza yazmaz.
- Ayrı branch: **wip/automatic-bus**, worktree: `.worktrees/automatic-bus`, commit: **bf89e78**.
- Sensör penceresi/durak eşleşmesi, store/outbox bağlantısı, ayrı SQL ve 11 senaryolu test taslağı yazıldı. Bu branch ana sürüme **birleştirilmedi**, SQL'i canlıya uygulanmadı; testleri root tarafından çalıştırılmadı, gerçek yolculuk doğrulanmadı.
- Devamda branch'in ürün/test/SQL değişikliklerini seçerek incele; eski kök görev MD'lerini geri getirme. Güncel ana şemayla uzlaştır, tek ağır test kuralıyla doğrula. Taslağı doğrudan teslim edilmiş sayma.


## Son commitler
- `761a58c`: profil yeniden deneme, klan etkileşimleri ve GM bildirim düğmesi.
- `2336226`: doğrulanmış canlı GM bildirim migration10 ve önceki teslim kaydı.
- Kullanıcı artık bağlı telefona APK yüklenmesini açıkça istedi; kurulum yönetimini root yapar.

- `bdbffba`: QR/NFC ekranını kaldırma ve üç sekmeli gezinme; yeni APK bağlı cihaza başarıyla kuruldu.

## Root son teslim teyidi
- Migration 11 açık BEGIN/ROLLBACK preflight başarıyla çalıştı; gövdesi birebir karşılaştırılıp `green_project_gm_steps_points_and_shame_fix` olarak canlıya uygulandı. Güvenlik danışmanı 0 ERROR / 14 WARN.
- Yeni APK SHA kontrolü releases dizininde geçti; bağlı ikinci telefona adb install -r: Success. MainActivity açıldı. Elle iki telefon senkron ve bildirim denemesi kullanıcıya ait.
- Claude Opus/Sonnet ortak kotası bitti; son uygulama düzeltmesi, AGY raporuna göre136 test ve derleme Flash High ile tamamlandı.
- Adım Ayarla600000 eski puansız kaydı onarır; tekrar aynı değerde çift ödül yok. Adım Ekle sınırı100000;600000 için Ayarla kullanılır.
- Detaylı sunum docs/SUNUM_DETAYLI_REHBERI.md değil, **docs/SUNUM_DETAYLI_REHBER.md** yolunda; basit rehber korunuyor.

## Dar Hata Teşhis ve Çözümü — Utanç Tablosuna Giriş (Migration 12 & GM Araç Cezası Eylemi)
- **Kök Neden:**
  - Mobil uygulamadaki `AdminPanelScreen` içindeki tüm test butonları (`[DEMO] 68 km/sa araba/taksi yakala`, `[DEMO] 68 km/sa taksi`) çağrıları `demo: true` ile çalıştırmaktadır.
  - `AppStore.evaluateVehicle` fonksiyonu `demo: true` olduğunda `SupabaseService.instance.recordVehiclePenalty` çağrısını atlamakta, ceza yalnızca o telefonun yerel belleğinde kalmakta, Outbox'a veya canlı Supabase'e hiçbir kayıt iletilmemektedir.
  - Canlı sunucu ortak snapshot'ı (`v_global_shame_board`) veritabanındaki `public.users.weekly_car_taxi_trips > 0` şartına bağlı olduğu için kullanıcının hesabı sunucu listesine girememektedir.
  - Ayrıca mevcut GM panelinde (`rpc_universal_gm_action`) hedef kullanıcıya araç/taksi cezası işleyecek yetkili bir yönetici eylemi bulunmamaktaydı.
- **Somut Çözüm (Yetkili GM Eylemi & Güvenlik Koruması):**
  - Uygulanmış `migration11` gövdesine dokunulmadan, artımlı `supabase/migrations/12_gm_vehicle_penalty.sql` hazırlandı.
  - `rpc_universal_gm_action` içine yetkili `add_vehicle_penalty` (ve `record_vehicle_penalty`) eylemi eklendi:
    - Yalnızca `server_admins` tablosunda kayıtlı yöneticiler çağırabilir (yetkisiz çağrı `RAISE EXCEPTION` ile engellenir; keyfi unauth ceza veya admin bypass yok).
    - Sayısal mesafe aralığı kontrolü (0.1 km - 500 km, varsayılan 8.5 km).
    - Mesafe başına CO₂ israfı: `ROUND(distance_km * 0.192, 2)` (en az 0.01 kg).
    - `users.weekly_car_taxi_trips` (+1), `users.weekly_car_taxi_km`, `users.weekly_wasted_co2_kg` artırılır; klan varsa `clans.weekly_wasted_co2_kg` güncellenir.
    - Puan, altın ve envanter KESİNTİSİ YAPILMAZ; tam olarak korunur.
    - `activities` tablosuna `car_taxi_penalty` (puan=0, co2=-israf) aktivite kaydı ve `admin_audit_trail` tablosuna idempotency kayıtları işlenir.
    - Tekrarlanan çağrılarda `duplicate: true` dönerek mükerrer ceza/çift sayaç artışı önlenir.
  - `tools/universal_gm/index.html` (PC GM Paneli) arayüzüne seçili kullanıcı için:
    - `🚗 Araba / Taksi Cezası Ekle (Utanç Tablosuna Yaz)` kontrolü ve mesafe girdisi eklendi.
  - Mobil uygulamada (`admin_panel_screen.dart`):
    - Demo butonları sessizce canlı cezaya çevrilmedi; buton alt başlıkları ve bildirim metinleri `[YEREL DEMO SİMÜLASYONU - Sunucu listesini etkilemez, canlı liste için PC GM Paneli]` olarak açık ve net hale getirildi.
  - Preflight testi: `supabase/preflight_gm_vehicle_penalty.sql` (BEGIN/ROLLBACK) ile yetkisiz ret, hedef kullanıcının `v_global_shame_board` görünümüne girmesi, idempotency, puan/altın bütünlüğü ve iki oturum + anonim tutarlılığı doğrulandı.
- **Test ve Analiz Durumu:**
  - `dart analyze`: **No issues found!** (0 hata, 0 uyarı).
  - Otomatik testler: `--no-pub --concurrency=1` ile **137/137 test BAŞARIYLA GEÇTİ** (`All tests passed!`).
  - Mobil build hemen başlatılmadı (kullanıcı talimatı gereği root canlı SQL uyguladıktan sonra yapılacak).

## Sunum öncesi son durum
- Migration 12 root tarafından BEGIN/ROLLBACK preflight ve fonksiyon gövdesi eşleşmesi doğrulandıktan sonra `green_project_gm_vehicle_penalty` adıyla canlıya uygulandı.
- PC GM panelinde seçili gerçek kullanıcıya açıkça yönetici testi olarak etiketlenmiş utanç bildirimi gönderilir; oyuncunun 10 altın ve günlük 1 mesaj kurallı mesajı değildir. Sunucu kaydı cihaz teslimi garantisi değildir. Araç mesafesi 0,1–500 km dışında veya boşsa reddedilir.
- Liderlik sorgularında kısmi veya tam hata artık başarılı bağlantı göstermez; utanç snapshot sorgusu bağımsız kalır. Realtime aboneliği yenilenirken ve servis kapatılırken bekleyen debounce zamanlayıcısı iptal edilir. Zamanlayıcı iptali doğrudan davranış testiyle doğrulanmadı.
- Dart analizi temiz; GM, Supabase, UI ve utanç kapsamındaki 43 test geçti. Panel JavaScript kontrolleri geçersiz/geçerli mesafe ve gerçek/demo hedef durumlarını doğruladı. Telefon bildirimi ve iki cihazda canlı görünüm kullanıcının elle testini bekliyor.
- Çevrimdışı Gradle debug derlemesi başarılı. `releases/YeSilAdim-debug.apk`: 173.964.791 bayt; SHA-256 `9cc672f8876ec475702d2c7c14fe849b94fd167e7c72fc3356f39212bbdbbe31`; checksum doğrulandı. Kurulum root tarafından yürütülür.

- Root son kurulum: bağlı telefonda adb install --no-streaming -r Success; veriler korunarak MainActivity açıldı. Son güvenlik danışmanı 0 ERROR /14 WARN. Yeni ürün değişikliği yok; kullanıcı elle test edecek.
