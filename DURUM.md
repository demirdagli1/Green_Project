# Yeşil Adım (EcoClan) — Durum ve Teslim Raporu

**Tarih / Saat:** 30 Ekim 2026, 21:24 (Europe/Istanbul)  
**Model & Yürütme:** AGY Argon Medium  
**Cihaz:** Samsung SM-A346E (`R6CWB01ASJT`), Android 16 / API 36 (`adb shell getprop ro.build.version.release` = 16, `ro.build.version.sdk` = 36)  
**Paket Kimliği:** `com.yesiladim.ecoclan.green_project`

---

## 1. Doğrulama Komutları ve Sonuçları

| Aşama | Komut / Araç | Sonuç | Kanıt Dosyası |
|---|---|---|---|
| **Statik Analiz** | `dart analyze` (Yerel Dart / Flutter SDK) | **0 hata, 0 uyarı** (Temiz) | [evidence/analyze.log](evidence/analyze.log) |
| **Birim & İş Kuralları Testleri** | `flutter test test/rules_test.dart --concurrency=1` | **20 test geçti** | [evidence/test_all.log](evidence/test_all.log) |
| **Durum & Kalıcılık Testleri** | `flutter test test/store_test.dart --concurrency=1` | **32 test geçti** | [evidence/test_all.log](evidence/test_all.log) |
| **Arayüz & Akış Testleri** | `flutter test test/ui_flow_test.dart --concurrency=1` | **6 test geçti** (küçük ekran 320x568 + textScale 1.6 ve donanım köprüsü regresyon testi dahil) | [evidence/test_all.log](evidence/test_all.log) |
| **Toplam Test Başarısı** | `flutter test --concurrency=1` | **58 / 58 test BAŞARILI** (0 hata) | [evidence/test_all.log](evidence/test_all.log) |
| **Offline APK Derleme** | `cd android && ./gradlew assembleDebug --offline --no-daemon --max-workers=1 -Dorg.gradle.parallel=false` (JDK 17) | **BUILD SUCCESSFUL** | [evidence/build_debug_latest.log](evidence/build_debug_latest.log) |
| **Cihaz Kurulumu & Çalıştırma** | `adb install -r build/app/outputs/flutter-apk/app-debug.apk` | **Success** | [evidence/adb_logcat.log](evidence/adb_logcat.log) |

---

## 2. Kullanılan Yerel Araç Yolları

- **Flutter SDK:** `/home/girdap/Masaüstü/WordMaster/.tools/flutter/bin/flutter`
- **Dart SDK:** `/home/girdap/Masaüstü/WordMaster/.tools/flutter/bin/cache/dart-sdk/bin/dart`
- **Pub Cache:** `/home/girdap/Masaüstü/WordMaster/.tools/pub-cache`
- **JDK 17:** `/home/girdap/Masaüstü/WordMaster/.tools/jdk17`
- **Android SDK:** `/home/girdap/Masaüstü/itiraf/.tools/android-sdk`
- **Platform Tools (ADB):** `/home/girdap/Masaüstü/itiraf/.tools/android-sdk/platform-tools/adb`

---

## 3. Gerçek vs. Demo vs. Eksik Özellik Ayrımı

### A. Gerçek (Doğrulanan ve Çalışan)
1. **Yerel Veri ve Kalıcılık (`SharedPreferences`):**
   - Kullanıcı profili, klan seçimi, yerel cihaz UUID kimliği.
   - Haftalık ve tüm zamanlar puanları, önlenen CO₂ miktarı.
   - Kazanılan ve harcanan altın bakiyesi, kuşanılan kozmetikler (`equippedAvatar`, `equippedFrame`, `equippedPet`).
   - Günlük adım sayacı, seri (`streak`), son kayıt zaman damgaları.
   - Transit biniş geçmişi ve durak bazlı 45 dakikalık cooldown takibi.
   - Bozuk JSON / kayıt durumunda güvenli sıfırlama dayanıklılığı.
2. **İş Kuralları & Puanlama Motoru:**
   - Adım puanlama eşikleri (0 / 900 / 999 / 1000 / 1999 / 2000), kadans hile eşiği (>185 adım/dk ret), GPS sıçrama filtreleme.
   - Bisiklet hızı (35 km/sa ortalama / 50 km/sa anlık ret; >25 km/sa hızda `0.12` ivmeölçer varyans eşiği), CO₂ tasarruf hesabı.
   - Araba/taksi tespiti (>30 km/sa araç hızı, son 45 dk transit varsa ceza iptali, yoksa harcanan CO₂ hesabı).
   - Bireysel lig kademeleri (`Karbonmonoksit`, `Karbondioksit`, `Azot`, `Oksijen`, `Ozon`, `Sönmez Biyosfer`) ve klan lig eşikleri.
   - Hibrit klan puanı formülü (`0.6 × ToplamPuan + 0.4 × 50 × ÜyeOrtalaması`), 5 üyeden az klanların sıralama dışı bırakılması.
   - Utanç tablosu isim maskeleme algoritması (`NameMasker`; görsel gizleme sağlar, hukuki uyumluluk garantisi değildir).
3. **Fiziksel Cihaz ve Donanım Köprüsü (`com.yesiladim.ecoclan/hardware`):**
   - Android 16 (API 36) cihazda (`Samsung SM-A346E`) gerçek donanım yetenekleri (`stepCounter`, `accelerometer`, `gps`, `locationEnabled`, `nfc`, `nfcEnabled`, `sdk: 36`) ve izin durumları (`activity`, `location`, `notifications`) sorgulanmakta ve Ana Sayfa kartında gösterilmektedir.
   - `dumpsys notification` ile gerçek Android sistem bildirimi (`NotificationChannel` / `StatusBarNotification`) doğrulandı.
   - Küçük ekran (320x568) ve %160 büyük font (`textScale: 1.6`) altında taşmasız (`RenderFlex overflow: 0`) dinamik yerleşim.

### B. Demo Olarak Sunulan Özellikler
1. **Rakipler & Klan Sıralaması:** Canlı bir veritabanı bağlantısı olmadığı için liderlik tablosundaki diğer yarışmacılar ve klan puanları şartnameye uygun tohum verileriyle simüle edilmektedir. Kullanıcı ("Sen") ise gerçek yerel verileriyle yarışır.
2. **Transit QR / NFC Doğrulama:** Fiziksel durak QR kodları veya NFC etiketleri bulunmadığında, kullanıcı arayüzündeki manuel durak kodu girişi ve demo simülasyonu ile transit biniş akışı ve 45 dk cooldown kuralı test edilebilmektedir.
3. **Jüri/Admin Paneli:** Demo ortamında hafta atlatma (`Haftayı Bitir & Puanları Altına Çevir`), sensör simülasyonu (+334 adım, GPS simülatörü) ve klan yönetimi yerel kalıcı depolama üzerinde çalışmaktadır.

### C. Eksikler ve Canlı Ortam Sınırlamaları
1. **Canlı Supabase Backend:** Canlı Supabase projesi bağlantısı olmadığı için sunucu tarafı RLS ve cihazlar arası anlık Realtime senkronizasyonu doğrulanmamıştır (istemcide `service_role` kullanılmaz; E-posta/SMS/OTP zaten kapsam dışıdır).
2. **Kamera QR Tarayıcı:** Yerel önbellekte kamera QR eklentisi bulunmadığı için kamera donanımı doğrudan açılmamakta, yerine standart uyarı ve manuel payload girişi devreye girmektedir.
3. **Arka Plan Sensör / Fiziksel Hareket Sınırları:** Uygulama kapalıyken arka planda sürekli adım ve GPS toplama garantisi yoktur; sensörler yalnızca uygulama ön plandayken dinlenir. Fiziksel yürüyüş/bisiklet/NFC etiket okutma testleri kullanıcı doğrulamasına tabidir.

---

## 4. Ekran Görüntüsü Kanıtları (Physical Device: Samsung SM-A346E)

Tüm ekran görüntüleri gerçek cihaz üzerinden `adb screencap` ile çekilerek `evidence/` dizinine kaydedilmiştir:

1. [evidence/screen_01_launch.png](evidence/screen_01_launch.png): Onboarding & Klan Seçimi
2. [evidence/screen_02_utanc.png](evidence/screen_02_utanc.png): Utanç Tablosu (Maskeli İsimler & Harcanan CO₂)
3. [evidence/screen_03_gurur.png](evidence/screen_03_gurur.png): Gurur Tablosu (Bireysel ve Klan Ligleri)
4. [evidence/screen_04_home.png](evidence/screen_04_home.png): Ana Sayfa (Adım Sayacı, Sensör/Donanım Durumu, Lig Kartı, CO₂ Tasarrufu)
5. [evidence/screen_06_shop.png](evidence/screen_06_shop.png): Kozmetik Mağazası & Altın Bakiyesi
6. [evidence/screen_07_admin.png](evidence/screen_07_admin.png): Jüri / Test Admin Paneli
