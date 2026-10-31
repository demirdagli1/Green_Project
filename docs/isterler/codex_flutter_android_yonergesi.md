# 🚀 YEŞİL ADIM (ECOCLAN) — FLUTTER ANDROID UYGULAMASI GELİŞTİRME YÖNERGESİ (`AGENTS.md`)

> **AI / CODEX / AGY AJANI İÇİN KESİN TALİMAT:**
> Sen kıdemli bir Flutter (Android) ve Supabase Full-Stack geliştiricisisin. Bu doküman, **KTÜ Yeşil Gelecek Hackathonu** kapsamında geliştirilecek olan **Yeşil Adım (EcoClan)** Android mobil uygulamasının uçtan uca teknik şartnamesidir. Kullanıcıya soru sormadan, eksik yer bırakmadan (`// TODO` veya placeholder kullanmadan), aşağıda belirtilen klasör yapısını, paketleri, Supabase bağlantısını, sensör/hile algoritmalarını, UI ekranlarını ve uygulama içi Admin/Demo kontrol panelini **eksiksiz ve derlenebilir (build-ready) Flutter kodu** olarak üret.

## 1. PROJE ÖZETİ VE TEMEL İŞLEYİŞ

* **Amaç:** Kullanıcıları özel araç ve taksi yerine yürümeye, bisiklet sürmeye ve toplu taşımaya teşvik ederek karbon ayak izini azaltmak.
* **Motivasyon & Yöntem:** Davranışsal oyunlaştırma (Gamification). İnsanların rekabet ve kayıptan kaçınma dürtülerini kullanarak; adım attıkça, otobüse bindikçe ve bisiklet sürdükçe puan kazandırmak, klanlar arası liglerde yarıştırmak, Duolingo tarzı darlayıcı bildirimlerle dürtmek ve çok arabaya/taksiye binenleri **Utanç Tablosu (Shame Board)** ile ifşa etmek.
* **Platform & Teknoloji Yığını:**
  * **Framework:** Flutter (Dart 3.x, Material 3, Android odaklı)
  * **Backend & Realtime DB:** Supabase (`supabase_flutter`)
  * **State Management:** Riverpod (`flutter_riverpod`) veya Provider
  * **Yerel Depolama & Cihaz ID:** `shared_preferences`, `device_info_plus`, `uuid`
  * **Sensörler & Konum:** `pedometer` (Adımsayar), `geolocator` (GPS Hız ve Mesafe), `sensors_plus` (İvmeölçer / Accelerometer)
  * **Toplu Taşıma Okuyucu:** `mobile_scanner` (QR Kod), `nfc_manager` (NFC Etiket Okuma)
  * **Bildirimler:** `flutter_local_notifications` + Supabase Realtime Stream dinleyicisi (Admin panelinden tetiklenen bildirimleri anında telefonda göstermek için)

## 2. KULLANICI GİRİŞİ (ÜYELİKSİZ / ZERO-AUTH AKIŞI)

Hackathon hızı ve kullanım kolaylığı için e-posta/şifre/OTP üyeliği **KESİNLİKLE YOKTUR**:
1. Uygulama ilk açıldığında `device_info_plus` (veya `SharedPreferences` içinde saklanan bir UUID) ile cihaza özel benzersiz bir `device_id` üretilir.
2. Supabase `users` tablosunda bu `device_id` sorgulanır.
3. Kayıt yoksa tek ekranlık şık bir **"Hoş Geldin! İsmin ne?"** ve **"Klanını Seç"** (Örn: *KTÜ Kanuni*, *KTÜ OF*, *KTÜ Dağcılık Kulübü*, *ODTÜ*, *Sincanlılar Derneği*, *Kırıkkale_45*) ekranı çıkar.
4. Kullanıcı adını yazıp klanını seçtiği an `users` tablosuna kaydedilir ve doğrudan Ana Sayfaya (`HomeScreen`) yönlendirilir.

## 3. PUAN SİSTEMİ, SENSÖR KURALLARI VE EDGE-CASE (HİLE) KORUMALARI

Uygulama içindeki `ActivityValidationService` sınıfı aşağıdaki kuralları birebir işletmelidir:

### 3.1. Yürüyüş ve Basamaklı Adım Ödülü (1.000 Adım = 5 Puan)
* **Kural:** Her **1.000 adım = 5 Puan** kazandırır. Küsuratlı adımlar puan vermez ancak ilerleme çubuğunda gösterilir.
* **Psikolojik Dürtme (Nudge):** 900 adım atan kişi puan alamaz; 100 adım daha atıp 1.000'e tamamladığında +5 puan alır. Ana sayfada sürekli: `"🎯 Sonraki +5 puana sadece X adım kaldı!"` (`1000 - (steps % 1000)`) dinamik metni gösterilir.
* **Streak (Seri) Kuralı:** Bir gün içinde **en az 6.000 adım** atan kullanıcının `streak_days` sayacı +1 artar ve günlük alev ikonu yanar.
* **Edge-Case (Telefonu Elde Sallama Hilesi - Shake Spoofing):**
  * Adım kadansı (dakikadaki adım sayısı) `> 185 adım/dk` ise veya `sensors_plus` ivmeölçer verisinde aşırı simetrik el sallama frekansı (`> 3.5 Hz`) varken GPS konum değişimi `0 metre` ise bu adımlar hile sayılır ve ekrana `"Telefonu sallayarak sadece kol kası yaparsın, kalk yürü!"` uyarısı basılır.

### 3.2. Toplu Taşıma (NFC ve QR Kod = 3 Puan)
* **Kural:** Otobüse veya kampüs ringine binen kullanıcı telefondan **NFC** okutarak veya **QR Kod** taratarak **+3 Puan** kazanır.
* **Doğrulama:** Okutulan QR (`YESILADIM://TRANSIT/TRB-KTU-01...`) veya NFC UID, Supabase `transit_stops` tablosuyla eşleşir. İlgili hattın ortalama mesafesine göre önlenen CO₂ miktarı (Örn: `1.22 kg CO₂`) kullanıcının ve klanının hanesine eklenir.
* **Edge-Case (Aynı QR/NFC'yi Defalarca Okutma Hilesi - Farming):**
  * Bir kullanıcı aynı durak/otobüs QR veya NFC kodunu **45 dakika içinde sadece 1 kez** okutabilir (`cooldown`). Süre dolmadan tekrar okutursa `"Aynı otobüsü iki kere mi satın aldın? Sonraki biniş puanı için X dk bekle!"` hatası döner.

### 3.3. Bisiklet Sürüşü (1 km = 1 Puan)
* **Kural:** Bisiklet modunda sürülen her **1 km = 1 Puan** kazandırır ve km başına `0.19 kg CO₂` tasarrufu yazar.
* **Edge-Case (Arabayla Giderken Bisiklet Açma Hilesi):**
  * `geolocator` ile anlık ve ortalama hız, `sensors_plus` ile ivmeölçer varyansı (`accel_variance`) kontrol edilir.
  * **Kural 1 (Hız Tavanı):** Bisiklet hızı **50 km/s** (veya ortalama 35 km/s) üzerine çıkarsa (`Saatte 50 km giden bisiklet olmaz!`) aktivite anında `rejected_speed_spoof` olarak reddedilir.
  * **Kural 2 (İvmeölçer Kontrolü):** Hız > 25 km/s iken ivmeölçer titreşim varyansı çok düşükse (`σ² < 0.12`, yani pedal/yol titreşimi yok, pürüzsüz araba süspansiyonu var) sistem kullanıcının arabada olduğunu anlar, puanı iptal eder ve aktiviteyi doğrudan **Araba/Taksi Cezası (`car_taxi_penalty`)** olarak kaydeder!

### 3.4. Otomobil / Taksi Tespiti ve CO₂ Suçluluk Bildirimi
* **Kural:** Kullanıcının GPS hızı yüksek ve sabitse (`V_ort > 30 km/s`), adım sayısı artmıyorsa ve son 45 dakika içinde okutulmuş bir **Otobüs NFC/QR kaydı yoksa**, sistem kullanıcının **Özel Araç veya Taksi** ile gittiğini tespit eder.
* **Hesaplama ve Bildirim:** Gidilen mesafe (`km`) × `0.192 kg CO₂` üzerinden harcanan karbon hesaplanır. Yolculuk sırasında veya bittiği an kullanıcıya şu bildirim fırlatılır:
  > `"🚕 Yakalandın! Son aktiviteyi araba/taksi yerine toplu taşımayla gitseydin X.XX kg CO₂ tasarruf yapardın aslında!!! Utanç tablosuna yazıldın!"`
* Kullanıcının `weekly_car_taxi_trips` (+1) ve `weekly_wasted_co2_kg` değerleri artırılır.

## 4. LİG, KLAN, UTANÇ TABLOSU VE ALTIN EKONOMİSİ

### 4.1. Bireysel ve Klan Ligleri (Ayrı İsimlendirme ve Logolar)
Görsel tasarımlara birebir sadık kalınarak **Demir/Bronz/Gümüş/Altın İSİMLERİ KULLANILMAYACAKTIR**. Onların yerine aşağıdaki 6 aşamalı atmosferik lig sistemi kullanılacaktır:

| Seviye (Tier) | Bireysel Lig İsimleri (`individual`) | Klan Ligi İsimleri (`clan`) | Tema Rengi (Hex) |
| :---: | :--- | :--- | :---: |
| **1** | **Karbonmonoksit** (0+ P) | **Kül Birliği** (0+ P) | `#8C8275` (Kül Gri) |
| **2** | **Karbondioksit** (150+ P) | **Sis Loncası** (2.500+ P) | `#8B5A2B` (Fabrika Kahve) |
| **3** | **Azot** (350+ P) | **Akım Cephesi** (6.000+ P) | `#4A6070` (Çelik Mavi) |
| **4** | **Oksijen** (650+ P) | **Koruyucu İttifak** (12.000+ P) | `#2CE5B5` (Turkuaz Yeşil) |
| **5** | **Ozon** (1.100+ P) | **Ozon Muhafızları** (25.000+ P) | `#5B6EE1` (Atmosfer Moru) |
| **6** | **Sönmez Biyosfer** (1.800+ P) | **Biyosfer Konseyi** (50.000+ P) | `#589A42` (Zümrüt & Altın) |

### 4.2. Klan Sistemi ve Puanlama
* Kullanıcılar bir klana katılabilir veya yeni klan oluşturabilir (*KTÜ Kanuni*, *KTÜ OF*, *ODTÜ*, *Koç Üni*, *Sabancı Üni*, *İTÜ*, *YTÜ*, *Gazi Üni*, *KTÜ Dağcılık Kulübü*, *Sincanlılar Derneği*, *Kırıkkale_45*).
* Klanın gücü üyelerinin haftalık toplam puanı ile ölçülür (Ayrıca sıralama ekranında `[ Toplam Puan | Hibrit Normalize Puan ]` filtresi bulunur; hibrit formül: `(Toplam Puan * 0.6) + (Üye Ortalaması * 50 * 0.4)`).
* Eğer klanın üye sayısı 5'den az ise yetersiz üye deyip sıralamaya alma.

### 4.3. Utanç Tablosu (Shame Board) — Maskeli İfşa Sistemi
* Hem **Klan Sıralaması** hem de **Bireysel Sıralama** içinde kırmızı renkli bir **`🚨 Utanç Tablosu`** sekmesi vardır.
* O hafta en çok otomobile veya taksiye binen (`weekly_wasted_co2_kg` ve `weekly_car_taxi_trips` değeri en yüksek olan) kullanıcılar listelenir.
* **Gizlilik Kuralı:** Utanç tablosundaki kullanıcıların **sadece ilk 3 harfi ve yıldız (`Ber***`, `Pel***`, `Oğu***`)** ile **profil fotoğrafı (avatarı)** gözükür.
  * Dart yardımcı fonksiyonu: `String maskShameName(String name) => '${name.substring(0, name.length >= 3 ? 3 : name.length)}***';`

### 4.4. Haftalık Sıfırlama, Geçen Haftanın Şampiyonu ve Altın (Gold) Mağazası
* Bireysel puanlar ve klan puanları her hafta sıfırlanır.
* **Puanların Altına Dönüşmesi:** Hafta bittiğinde kullanıcının o hafta topladığı `weekly_points` birebir **Altın (`gold_coins`)** bakiyesine eklenir.
* **Kozmetik Mağazası (`ShopScreen`):** Kullanıcılar altınları ile **Avatar**, **Profil Çerçevesi** (*Oksijen Neon Çerçevesi*, *Sönmez Biyosfer Tacı*) ve **Pet / Yoldaş** (*Yürüyen Çam Fidanı*, *Biyo-Mekanik Arı*, *Orman Tilkisi*) satın alıp kuşanabilir.
* **Geçen Haftanın Şampiyonu:** Ana sayfanın üst kısmında geçen haftanın bireysel ve klan şampiyonu (`👑 Geçen Haftanın Şampiyonları: Zeynep Kaya & KTÜ Kanuni`) özel bir vitrin kartında gösterilir.

## 5. EKRAN TASARIMLARI VE UI / UX KURALLARI (GÖRSELLERE BİREBİR UYUM)

Uygulama arayüzü açık tema (ferah beyaz/buz mavisi kartlar, `#F4F7FE` arka plan, `#635BFF` mor ve `#10B981` zümrüt yeşili vurgular, `24px` yuvarlatılmış kart köşeleri) ile tasarlanacaktır:

1. **Ana Sayfa (`HomeScreen`):**
   * **Üst Başlık:** Sol üstte `"Daha yeşil bir gelecek için adım at!"` (mor-lacivert tipografi), sağ üstte dünya/yaprak illüstrasyonu ile `🔥 X Gün` (Streak) ve `🪙 X Altın` rozetleri.
   * **Geçen Haftanın Şampiyonu Banner'ı:** Başlığın hemen altında altın sarısı/yeşil gradyanlı kompakt kart.
   * **Günlük Adım Sayısı Kartı:** Solunda yeşil ayakkabı ikonu, ortada büyük fontla `6.666 adım`, altında yeşil ilerleme çubuğu (`LinearProgressIndicator`) ve hemen altında **900->1000 adım teşvik metni**: `"🎯 Sonraki +5 puana sadece 334 adım kaldı!"`.
   * **İkili Lig Kartları (Yan Yana 2 Grid):**
     * Sol Kart: **Lig klan** — Altıgen mor rozet + `"Ozon Muhafızları"`
     * Sağ Kart: **Lig birey** — Altıgen turkuaz rozet + `"Oksijen"`
   * **İkili Sıralama Kartları (Yan Yana 2 Grid, Tıklanabilir):**
     * Sol Kart: **Klan sırası** (`Bu hafta 1.`) -> Tıklanınca `LeaderboardScreen(initialTab: 'clan')` açılır.
     * Sağ Kart: **Birey sırası** (`Bu hafta 4.`) -> Tıklanınca `LeaderboardScreen(initialTab: 'individual')` açılır.
   * **Önlenen CO₂ Kartı (En Alt):** Yaprak ikonu ile **`Önlenen CO₂ Salımı: 12,4 kg`** (Kesinlikle "Kurtarılan O2" yazma, "Önlenen CO₂" yaz!) ve yanında `"🌲 6 Ağaç"` rozeti.

2. **Sıralamalar ve Utanç Tablosu Ekranı (`LeaderboardScreen`):**
   * En üstte `"Tüm zamanlar skoru >"` butonu ve yanında **`[ 🏆 Gurur Tablosu | 🚨 Utanç Tablosu ]`** geçiş anahtarı.
   * Ortada yatay dizilmiş **6 adet altıgen Lig Sembolü** (Seçili sekmeye göre Bireysel ise `Karbonmonoksit -> Sönmez Biyosfer`, Klan ise `Kül Birliği -> Biyosfer Konseyi` isimleriyle).
   * Liste görünümü: Gurur modunda yeşil yaprak ikonuyla puanlar (`125.430`, `98.210`...); Utanç Tablosu modunda ise dumanlı kırmızı kartlarla maskeli isimler (`Pel***`, `Ber***`), avatar, haftalık araba/taksi biniş sayısı ve israf edilen CO₂ (`44.2 kg CO₂`).
   * En altta sabit `[ Bireysel | Klan ]` geçiş (segmented) butonu.

3. **Aktif Sürüş / NFC & QR Okutma Modali (`TransitAndBikeSheet`):**
   * Alt navigasyon barının ortasındaki **`🚌 QR / NFC`** butonuna basılınca açılır.
   * Sekme 1: **Otobüs QR / NFC Okut** (Kamera ile QR okuma + NFC dinleme + Hızlı Test için listeden durak seçip okutma).
   * Sekme 2: **Bisiklet Modu Başlat** (Canlı GPS hız göstergesi `km/s`, ivmeölçer titreşim grafiği/durumu ve kazanılan km puanı).

4. **Mağaza ve Profil Ekranı (`ProfileAndShopScreen`):**
   * Kullanıcının avatarı, seçili çerçevesi, aktif peti, cihaz ID'si ve altın bakiyesi.
   * Altınla satın alınabilir çerçeveler, avatarlar ve petler listesi.
   * Sağ üst köşede veya en altta **Jüri / Admin Kontrol Paneli (`AdminPanelScreen`)** giriş butonu.

5. **Uygulama İçi Admin & Jüri Simülasyon Paneli (`AdminPanelScreen`):**
   * Hackathon jürisine masa başında tüm özellikleri ve bildirimleri canlı kanıtlamak için uygulama içinde tam yetkili bir **Admin Paneli** ekranı bulunmalıdır:
     * **Duolingo Tarzı "Darlama" Bildirimi Gönderici:** Hedef kullanıcı veya klan seçip hazır şablonlarla (*"X kişisi seni geçti, sen de anca yat!"*, *"Biraz yürü ayağın açılsın, x gündür yürümüyosun"*, *"Bu ara hiç otobüse binmiyosun, hayırdır? Araba mı aldın???"*) anında `flutter_local_notifications` + Supabase `admin_notifications_log` üzerinden bildirim fırlatma.
     * **Canlı Sensör & Hile Simülatörü:**
       * `[+334 Adım Ekle (6.666 -> 7.000)]` -> +5 Puan ve konfeti tetikler.
       * `[🚌 101 Otobüs NFC/QR Doğrula]` -> +3 Puan ve +1.22 kg CO₂ ekler.
       * `[🚕 68 km/s Araba/Taksi Yakala]` -> *"Toplu taşımayla gitseydin 1.63 kg CO₂ tasarruf yapardın aslında!!!"* bildirimi atar ve kullanıcıyı Utanç Tablosuna sokar.
       * `[🚴‍♂️❌ 72 km/s Bisiklet Hilesi Test Et]` -> *"Saatte 72 km hızla bisiklet olmaz! İvme sensörü araba diyor!"* hatası verip puanı reddeder.
     * **Haftayı Bitir & Puanları Altına Çevir Butonu:** Supabase `admin_trigger_weekly_reset()` RPC fonksiyonunu çağırarak haftalık puanları altına (`gold_coins`) dönüştürür, haftalık puanları sıfırlar ve geçen haftanın şampiyonunu günceller.

## 6. ÖNERİLEN FLUTTER KLASÖR MİMARİSİ

```text
lib/
├── main.dart                          # Supabase init, Notification init, MaterialApp
├── core/
│   ├── constants/
│   │   ├── app_colors.dart            # Renk paleti ve lig renkleri
│   │   └── supabase_config.dart       # SUPABASE_URL ve SUPABASE_ANON_KEY
│   └── utils/
│       └── name_masker.dart           # Utanç tablosu ilk 3 harf maskeleme (Ber***)
├── models/
│   ├── app_user.dart                  # Kullanıcı modeli
│   ├── clan.dart                      # Klan modeli + Hibrit normalizasyon skoru
│   ├── league_tier.dart               # Bireysel ve Klan lig tanımları
│   ├── transit_stop.dart              # NFC / QR durak modeli
│   └── shop_item.dart                 # Avatar, Çerçeve, Pet mağaza modeli
├── services/
│   ├── supabase_service.dart          # Tüm DB CRUD, Realtime dinleme, Fallback Mock veri
│   ├── sensor_tracking_service.dart   # Pedometer, Geolocator, Accelerometer & Anti-cheat
│   └── notification_service.dart      # flutter_local_notifications + Duolingo bildirimleri
└── screens/
    ├── main_shell.dart                # BottomNavigationBar + Orta QR/NFC FAB
    ├── home/
    │   └── home_screen.dart           # Adım kartı, Ligler, Şampiyon banner, Önlenen CO2
    ├── leaderboard/
    │   └── leaderboard_screen.dart    # Bireysel/Klan Gurur & Utanç Tablosu (Shame Board)
    ├── transit_bike/
    │   └── qr_nfc_bike_modal.dart     # Otobüs QR/NFC tarayıcı ve Bisiklet GPS takipçisi
    ├── shop_profile/
    │   └── shop_profile_screen.dart   # Altın harcama, Avatar/Çerçeve/Pet mağazası
    └── admin/
        └── admin_panel_screen.dart    # Bildirim gönderme, Sensör/Taksi simülasyonu, Haftalık Reset
```

## 7. `pubspec.yaml` BAĞIMLILIKLARI

```yaml
dependencies:
  flutter:
    sdk: flutter
  supabase_flutter: ^2.5.0
  flutter_riverpod: ^2.5.1
  shared_preferences: ^2.2.3
  device_info_plus: ^10.1.0
  uuid: ^4.4.0
  pedometer: ^4.0.2
  geolocator: ^12.0.0
  sensors_plus: ^5.0.1
  mobile_scanner: ^5.1.1
  nfc_manager: ^3.4.0
  flutter_local_notifications: ^17.1.2
  google_fonts: ^6.2.1
  lucide_icons: ^0.257.0
```

## 8. OFFLINE / FALLBACK MOCK-UP GARANTİSİ (ÇOK ÖNEMLİ!)

Hackathon ortamında internet veya Supabase bağlantısı anlık kopabilir. Bu yüzden `SupabaseService` içinde **Offline-First / In-Memory Fallback** mekanizması bulunmalıdır:
* Eğer `SUPABASE_URL` henüz girilmemişse veya ağ hatası alınırsa uygulama **ASLA ÇÖKMEMELİDİR**.
* Hazır mock-up veriler (`KTÜ Kanuni - 125.430 P`, `KTÜ OF - 98.210 P`, `ODTÜ - 87.540 P`, `Sen (Efe) - 6.666 adım / 8.960 P / 12.4 kg CO₂`, Utanç tablosundaki `Pel***`, `Ber***`, `Oğu***`, Trabzon otobüs durakları `TRB-KTU-01`, `TRB-BLD-101` ve mağaza ürünleri) doğrudan uygulama içindeki yerel state üzerinden de aynı şekilde çalışmaya devam etmelidir.
* Admin panelinden yapılan tüm işlemler (bildirim gönderme, +334 adım ekleme, taksi cezası kesme, haftalık sıfırlama) hem Supabase'i hem de yerel state'i anında güncellemelidir.
