# Yeşil Adım (EcoClan)

Yeşil Adım, sürdürülebilir kentsel hareketliliği (yürüme, bisiklet, toplu taşıma) teşvik eden, klan temelli gamification ve karbon ayak izi takip mobil uygulamasıdır.

## 🚀 Proje Durumu ve Özet

- **Statik Kod Analizi:** `dart analyze` ile 0 hata, 0 uyarı
- **Test Kapsamı:** **94 / 94 test başarılı** (`rules_test`, `store_test`, `ui_flow_test`, `gm_panel_test`, `leaderboard_window_test`, `phase_b_c_test`)
- **Derleme Modu:** Tamamen çevrimdışı (offline Gradle, JDK 17, AGP, `--no-daemon --max-workers=1 -Dorg.gradle.jvmargs="-Xmx2048m"`)
- **Fiziksel Cihaz Uyumluluğu:** Samsung SM-A346E (Android 16 / API 36)
- **Ekran Uyum Testi:** 320x568 küçük ekran + %160 metin boyutu altında taşmasız dinamik yerleşim.

---

## 📱 Temel Modüller ve Özellikler

1. **Onboarding & İzin Akışı:**
   - İlk açılışta tek izin-deneme akışı (`welcome_screen.dart`), ana sayfadan teknik sensör kartı kaldırılmıştır.
   - Profil sayfası altında jüri/admin ve donanım telemetrisi seçenekleri korunmaktadır.

2. **Aktivite Takibi ve Sensör Telemetrisi:**
   - Adım sayacı ve 1000 adımda bir +5 puan mekanizması.
   - Kısa yürüyüşlerde adım kaybını önleyen 30 saniyelik zaman aşımı penceresi.
   - Kadans (>185 adım/dk) ve GPS hareketsizlik/sallama hilesi koruması.
   - Ham telemetri takibi (donanım sayacı, baseline, varyans, GPS fix/doğruluk).

3. **Toplu Taşıma (QR & NFC):**
   - Alt gezinme çubuğunda bağımsız sekme (`[0] QR/NFC`).
   - Tek biniş için +3 puan ve sabit CO₂ tasarrufu; 45 dakikalık durak bazlı ortak cooldown kuralı.

4. **Liderlik Tablosu & Gezinme (Aşama B):**
   - Yatay lig buton/filtre şeridi kaldırılmıştır.
   - Satır düzeni: `#RANK | AVATAR | İSİM (altında klan) | LİG LOGOSU BADGE | PUAN`.
   - Sabit sol Gurur/Utanç seçicisi ve sağ zaman (Haftalık/Tüm Zamanlar) kontrolü.
   - Klan sıralamaları tamamen hibrit formül ile hesaplanır: `0.6 * toplam + 0.4 * 50 * üye_ortalaması` (<5 üye sıralama dışı).
   - Pencereleme (Top 10 + kendi satırı ± 1 komşu) ve 120 satırlık test fixture ile doğrulanmış `LeaderboardWindow`.
   - 4 öğeli alt menü: `QR/NFC | Ana Menü (varsayılan) | Sıralamalar | Profil`. Floating FAB kaldırılmıştır.

5. **Ana Sayfa & Profil (Aşama C):**
   - Henüz kesinleşmemiş haftalık şampiyonlar için açık `[DEMO]` etiketi fallback desteği.
   - Birleşik klan ve bireysel lig kartları: Tıklanınca sıralama sekmesine geçiş ve kendi satırını vurgulama.
   - Maskeli Utanç Tablosu özeti (`Pel***`) ve tam tabloya doğrudan geçiş.
   - Paket indirmeden Android Photo Picker / OpenDocument native köprüsü ile profil fotoğrafı seçme/kaldırma ve yeniden başlatma kalıcılığı.
   - Max 160 karakter biyografi düzenleyici (Türkçe ve emoji güvenli). Normal profilde cihaz UUID gizlenmiştir.
   - İnsan tarafından okunabilir kozmetik isimleri ve asset slot fallback desteği.

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

3. **Güvenlik Mimarisi & Sözleşme:**
   - Release modunda otomatik devre dışı (`kReleaseMode`).
   - Origin kontrolü (`localhost` / `127.0.0.1:8088`), 64 KB streaming sınırı, idempotent duplicate ve conflict koruması.
   - Profil alanları (`bio`, `photoPath`) durum JSON'unda sunulur; `set_bio` komutu mevcuttur.

---

## 📦 Derleme ve Test

```bash
# Testleri çalıştırma (offline, tek worker):
export FLUTTER_NO_VERSION_CHECK=true CI=true
flutter test --no-pub --concurrency=1

# Statik analiz:
dart analyze

# Offline APK derleme (2GB Heap, tek worker):
cd android
./gradlew assembleDebug --offline --no-daemon --max-workers=1 -Dorg.gradle.jvmargs="-Xmx2048m"

# Cihaza veri koruyarak yükleme:
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```
