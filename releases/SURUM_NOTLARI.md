# Yeşil Adım — Sürüm Notları (Canlı Supabase İstemci & Mockup Paketi)

- **Tarih:** 31 Ekim 2026
- **Derleme Tipi:** Debug (Tamamen Çevrimdışı, 1 worker, 2GB JVM Heap)
- **Dosya Adı:** `YeSilAdim-debug.apk`
- **Dosya Boyutu:** ~149 MB (156.024.928 bayt)
- **SHA-256 Özeti:** `88ed75092fb803cc0eee35600d4b57dcf51eb6f0979b0ebfe81e9017dc3fb087`
- **Hedef Platform:** Android (arm64-v8a, armeabi-v7a, x86_64)

---

## 🌟 Bu Sürümde Eklenen Canlı Supabase İstemcisi
1. **Canlı Supabase Entegrasyonu:** `supabase_flutter: 2.17.2` bağımsız servis olarak eklendi.
2. **Anonymous Auth & Session Reuse:** Cihaz başına kalıcı anonim oturum, yeniden başlatmada oturum korunması.
3. **İlk Profil Senkronizasyonu (`rpc_sync_initial_profile`):** Legacy yerel profil ve puanların sunucuya güvenli taşınması; sunucu tek gerçek kaynaktır.
4. **Çevrimdışı Kuyruk (Pending Outbox):** Ağ kesintisinde olayların yerel saklanması, ağ gelince idempotent retry (`duplicate: true` koruması).
5. **Realtime & Anti-Echo:** Canlı bildirimler, klan güncellemeleri, şampiyonlar; kendi oturumumuzun döngüye girmesi engellendi.
6. **Liderlik Deduplication:** Sunucu kullanıcıları ve demo kullanıcıları ayrık, kullanıcı kendini iki kez görmez.
7. **Profil Durum Kartı:** Profil sayfasında canlı bağlantı/kuyruk durumu ve yenileme butonu.

---

## 🌟 Önceki Sürümde Tamamlanan Mockup & Logo Entegrasyonu

### 1. Bireysel Lig Logoları (1-6 PNG) Ortak Entegrasyonu
- `Logolar/logo-bireysel/` altındaki 6 adet PNG (`lig-bireysel-1.png` ... `lig-bireysel-6.png`) kod-native asset olarak eklendi:
  - 1: Karbonmonoksit
  - 2: Karbondioksit
  - 3: Azot
  - 4: Oksijen
  - 5: Ozon
  - 6: Sönmez Biyosfer
- Ortak bileşen `IndividualLeagueBadge` ile `BoxFit.contain` kullanılarak oran korundu; satırdaki rozet okunurluğu ve taşma engeli sağlandı.
- Ana sayfa bireysel kartı (34x34) ve gurur tablosu kullanıcı satırlarında (20x20) ortak bileşen bağlandı.
- **Klan Ayrımı:** Klan liglerine bireysel logolar atanmadı; klanlar dinamik renk ve kalkan rozetini korudu.
- Toplu `erasebg-transformed.png` dosyası kullanılmadı.

### 2. SQL Şeması ve Yerel Seed Entegrasyonu
- Sağlanan `supabase_schema_ve_mockup_veriler.sql` dosyası kaynak olarak alındı (canlı DB bağlantısı yok; dosya salt okunur seed referansıdır):
  - **15 Demo Kullanıcı:** SQL `users` tablosundaki gerçek satırlar (Zeynep Kaya 1. sıra, Berkecan Taksi ve Pelinsu Yılmaz utanç tablosu, vb.). 100'e tamamlamak için kullanıcı uydurulmadı.
  - **11 Klan:** SQL tamsayı ID'leri deterministik kalıcı string ID'lerle (`clan_ktu_kanuni`, `clan_ktu_of`, vb.) eşlendi. SQL dışı mevcut klan `clan_micro` (Yalnız Gezginler) ve kullanıcı klanları korundu.
  - **6 Transit Durağı:** `TRB-KTU-01`, `TRB-KTU-02`, `TRB-BLD-101`, `TRB-BLD-104`, `TRB-BLD-501`, `ANK-EGO-411` (+ legacy alias `TRB-OF-204`).
  - **8 Mağaza Ürünü:** `frame_oxygen_glow`, `frame_ozone_purple`, `frame_biosfer_gold`, `pet_pine_sprout`, `pet_robo_bee`, `pet_leaf_fox`, `ava_cycling_pro`, `ava_ktu_mountaineer`.

### 3. Sürümlü Veri Yükseltmesi (Seed v3) & İdempotentlik
- `seedVersion < 3` kontrolü ile eski kurulumlardan geçişte gerçek kullanıcı profili (`me`), adı, biyografisi, fotoğraf yolu, adımları, streak'i, altınları ve klan katkıları korundu.
- SQL'deki `Sen (Efe)` kaydı `isDemo: true` olan bağımsız demo kullanıcısı olarak eklendi; gerçek kullanıcının yerine geçirilmedi.
- İkinci load ve restart işlemleri tamamen **idempotenttir**; gerçek veriler tekrar yükleme veya periyot kontrolüyle ezilmez.

### 4. Legacy Ürün Aliasları ve Envanter Koruması
- Önceki sürümlerde satın alınmış eşyalar (`leaf_warrior`, `oxygen_frame`, `pine_seedling` vb.) yeni SQL slug'larıyla çift yönlü aliaslandı.
- Kullanıcıdan mükerrer altın çekilmez; kuşanılmış eşyalar profil ekranında insan okunur başlıklarıyla listelenir.

### 5. Transit QR ve NFC Normalizasyonu
- QR payload'larındaki `?sig=...` demo parametresi ayıklanarak canonical durak koduna indirgenir.
- Kolonlu (`04:A1:2B:...`) ve kolonsuz (`04A12B...`) hex NFC UID biçimleri durak koduna normalize edilir.
- QR ve NFC binişleri aynı durak üzerinde ortak 45 dakikalık cooldown kuralını paylaşır.

---

## 🧪 Doğrulama ve Test Raporu

- **Statik Kod Analizi:** `dart analyze` ➔ **0 issue (Hatasız ve Uyarısız)**
- **Otomasyonlu Testler:** `flutter test --no-pub --concurrency=1` ➔ **114 / 114 test BAŞARILI**
  - `rules_test.dart`: 20 test
  - `store_test.dart`: 32 test
  - `gm_panel_test.dart`: 13 test
  - `ui_flow_test.dart`: 6 test
  - `leaderboard_window_test.dart`: 12 test
  - `phase_b_c_test.dart`: 11 test
  - `phase_d_test.dart`: 9 test
  - `mockup_migration_test.dart`: 4 test
  - `supabase_integration_test.dart`: 7 test
  - `mockup_migration_test.dart`: 4 test (Veri yükseltmesi, kalıcılık, Sen (Efe) koruması, transit NFC UID normalizasyonu, lig sözleşmesi)
- **Çevrimdışı Android APK Derlemesi:** Tek worker / 2 GB JVM Heap ile **22 saniyede başarılı** (`releases/YeSilAdim-debug.apk`).

---

## ⚠️ Kullanıcı Elle Test ve Kapsam Notları
1. **Elle Cihaz Testleri Kullanıcıda:** Kullanıcının talimatı doğrultusunda telefona otomatik tıklama/kurulum yapılmamış, telefon mevcut durumunda bırakılmıştır.
2. **Kozmetik Grafikleri:** Kullanıcı tarafından sağlanacak avatar/çerçeve/pet PNG çizimleri henüz verilmediğinden insan okunur fallback rozetleri ve emojiler devrededir.
3. **Canlı Supabase:** Canlı backend veya uzak veritabanı kurulmamıştır; tüm veriler cihaz üzerinde yerel kalıcıdır.
