# Yeşil Adım (EcoClan)

Yeşil Adım, sürdürülebilir kentsel hareketliliği (yürüme, bisiklet, toplu taşıma) teşvik eden, klan temelli gamification ve karbon ayak izi takip mobil uygulamasıdır.

## 🚀 Proje Durumu ve Özet

- **Statik Kod Analizi:** `dart analyze` ile 0 hata, 0 uyarı
- **Test Kapsamı:** **71 / 71 test başarılı** (`rules_test`, `store_test`, `ui_flow_test`, `gm_panel_test`)
- **Derleme Modu:** Tamamen çevrimdışı (offline Gradle, JDK 17, AGP, `--no-daemon --max-workers=1`)
- **Fiziksel Cihaz Doğrulaması:** Samsung SM-A346E (Android 16 / API 36) üzerinde kurulum, canlı telemetri/sensör dinleyicileri, izin akışı ve yerel PC GM Paneli USB loopback testi doğrulandı.
- **Ekran Uyum Testi:** 320x568 küçük ekran + %160 metin boyutu altında taşmasız dinamik yerleşim.

---

## 📱 Temel Modüller ve Özellikler

1. **Onboarding & İzin Akışı:**
   - İlk açılışta toplu izin talebi (`welcome_screen.dart`), tekrar eden sistem uyarıları olmaksızın hızlı başlangıç.
   - Ana sayfada kalabalık yaratan teknik sensör kartı kaldırılmış, Profil sayfasının altına taşınmıştır.

2. **Aktivite Takibi ve Sensör Telemetrisi:**
   - Adım sayacı ve 1000 adımda bir +5 puan mekanizması.
   - Kısa yürüyüşlerde adım kaybını önleyen 30 saniyelik zaman aşımı penceresi.
   - Kadans (>185 adım/dk) ve GPS hareketsizlik/sallama hilesi koruması.
   - Ham telemetri takibi (donanım sayacı, baseline, varyans, GPS fix/doğruluk).

3. **Toplu Taşıma (QR & NFC):**
   - Tek biniş için +3 puan ve sabit CO₂ tasarrufu.
   - 45 dakikalık durak bazlı ortak cooldown kuralı (aynı durakta mükerrer biniş engeli).
   - Manuel payload girişi ve simülasyon desteği.

4. **Bisiklet ve Araç/Taksi Denetimi:**
   - Bisiklet sürüşlerinde mesafe bazlı puanlama ve >25 km/sa hızda ivmeölçer varyans eşiği (`0.12`). Net ceza ve ret açıklamaları.
   - Araç/taksi kullanımında (>30 km/sa) son 45 dk transit binişi yoksa harcanan CO₂ hesabı ve Utanç Tablosu kaydı; deterministik test seçeneği.

5. **Liderlik ve Utanç Tablosu:**
   - **Gurur Tablosu:** Bireysel ve klan bazlı haftalık/tüm zamanlar sıralamaları, hibrit normalize klan puanı hesabı (`0.6 × ToplamPuan + 0.4 × 50 × ÜyeOrtalaması`).
   - **Utanç Tablosu:** Harcanan CO₂ miktarına göre sıralama ve isim maskeleme (`Pel***`; yalnızca görsel gizleme sağlar, hukuki uyumluluk garantisi değildir).

6. **Kozmetik Mağazası & Envanter:**
   - Puanların altına dönüştürülmesiyle avatar, çerçeve ve evcil hayvan satın alma ve kuşanma.

---

## 🛠️ Yerel PC GM Kontrol Paneli (USB / ADB)

Harici web hosting gerektirmeyen, Android cihaz içinde yerel loopback (`127.0.0.1:8088`) üzerinden çalışan karanlık tema AppStore GM kontrol paneli:

1. **Port Yönlendirme:**
   ```bash
   adb forward tcp:8088 tcp:8088
   ```

2. **Erişim:**
   Uygulama içi Admin Panelinde gösterilen güvenlik tokenı ile tarayıcıdan açınız:
   ```
   http://127.0.0.1:8088/?token=<GM_TOKEN>
   ```

3. **Güvenlik Mimarisi:**
   - Release modunda otomatik olarak devre dışı bırakılır (`kReleaseMode`).
   - 401 yanıtlarında token bilgisi ifşa edilmez.
   - Sıkı Origin kontrolü (`localhost` / `127.0.0.1:8088`), phishing domain koruması.
   - 64 KB streaming gövde sınırlaması.
   - Komutlarda idempotent duplicate önleme ve çakışma (conflict) tespiti.
   - Katı sayısal sınır kontrolleri (adım, streak, altın).

---

## 📦 Derleme ve Test

```bash
# Testleri çalıştırma:
flutter test --concurrency=1

# Offline APK derleme:
cd android
./gradlew assembleDebug --offline --no-daemon --max-workers=1

# Cihaza yükleme:
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```
