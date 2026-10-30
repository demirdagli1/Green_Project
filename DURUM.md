# Yeşil Adım — doğrulanmış durum

30 Ekim 2026, revizyon02 / Aşama A, B, C ve D tamamlandı. Samsung SM-A346E, Android 16 / API 36 uyumlu. Yerel commitler yönetici tarafından tutulur, push yapılmaz. Kod AGY tarafından yazılmıştır.

## Revizyon02 / Tamamlanan Aşamalar (A, B, C, D)
- **Aşama A (Sensör Telemetrisi & PC GM Paneli):**
  - Donanım sensör callbackleri, baseline kaydı, 30 sn bekleyen adım penceresi, tek açılış izin akışı.
  - PC GM paneli (localhost:8088 / USB adb forward) token doğrulamalı tam kontrol sözleşmesi.
- **Aşama B (Sıralamalar & Gezinme):**
  - Yatay lig şeridi kaldırıldı.
  - `#RANK | AVATAR | İSİM (altında klan) | LİG LOGOSU | PUAN` kesin satır düzeni.
  - Sabit sol Gurur/Utanç ve sağ zaman kontrolü (layout shift yok).
  - Klanlar yalnızca hibrit formül (`0.6 * toplam + 0.4 * 50 * üye_ortalaması`, <5 üye hariç).
  - Top 10 + kendi satırı ± 1 komşusu, tek `…` ellipsis pencereleme (120 satırlık test fixture ile doğrulandı).
  - 4 öğeli alt menü: `QR/NFC (0) | Ana Menü (1, varsayılan) | Sıralamalar (2) | Profil (3)`. FAB kaldırıldı, PopScope Ana Menü'ye döner.
- **Aşama C (Ana Sayfa & Profil):**
  - Açık `[DEMO]` etiketli geçen haftanın şampiyonu fallback desteği.
  - Birleşik "Klanım & Sıram" ve "Bireysel Ligim & Sıram" kartları; tıklandığında ilgili sıralama listesini açıp kullanıcının kendi satırını vurgular.
  - Maskeli Utanç Tablosu özeti (`Pel***`) ve tam tabloya geçiş linki.
  - Paket indirmeden Kotlin Android Photo Picker / OpenDocument köprüsü üzerinden 1024x1024 downsampling ile profil fotoğrafı seçme/kaldırma ve restart kalıcılığı. Max 160 karakter bio düzenleyici. Normal profilde cihaz UUID gizlendi.
  - İnsan okunur kozmetik varlık slotları. GM paneli durum JSON'ında `bio` ve `photoPath` alanları ve `set_bio` komutu.
- **Aşama D (Otomatik Hareket Motoru):**
  - `AutoMotionEngine` durum makinesi: `idle`, `walking`, `potentialBike`, `cycling`, `limitedMode`.
  - Başlama histerezisi: 10 saniye ve 3 ardışık GPS fix boyunca 9-45 km/sa hız, düşük adım artışı ve ivme varyansı doğrulanmadan sürüş başlatılmaz.
  - Durma histerezisi: Kırmızı ışık / kısa duraklamada 45 saniyeye kadar tolerans; 45 sn hareketsiz kalırsa otomatik kaydedilir.
  - Manuel öncelik: Manuel sürüş başlatıldığında otomatik motor pasif kalır, sürüşü bozmaz.
  - Ana sayfada dinamik aktif sürüş kartı; "Bitir & Kaydet" ve "İptal Et" kontrolleri.
  - Çift ödül koruması: Bisiklet sürüşü adımları adım ödülünü tetiklemez; tekil `tripId` ile çifte puan önlenir.
  - Eksik/zayıf GPS (accuracy > 30m): Sınırlı moda geçer, muğlak durumda asla otomatik ceza vermez.
  - GM Paneli simülasyon komutları: `auto_motion_simulate`, `auto_motion_finish`, `auto_motion_cancel`.

## Kanıt ve Sınırlar
- **Statik Kod Analizi:** `dart analyze` ➔ **0 issue (Hatasız ve Uyarısız)**.
- **Test Kapsamı:** **103 / 103 test BAŞARILI** (`rules_test`: 20, `store_test`: 32, `gm_panel_test`: 13, `ui_flow_test`: 6, `leaderboard_window_test`: 12, `phase_b_c_test`: 11, `phase_d_test`: 9). Bağımsız son koşu: [final_verified_tests.log](evidence/final_verified_tests.log); bağımsız analiz: [final_analyze.log](evidence/final_analyze.log).
- **Offline APK Derlemesi:** Son bağımsız derleme tek worker / 2 GB Heap ile başarılı (12s). Kanıt: [final_build.log](evidence/final_build.log).
- **Teslim Edilen APK:** `releases/YeSilAdim-debug.apk` (yaklaşık 147 MB, SHA-256: `d7a2359c58a3260c7449be7622e69026db6e1ea292d3f4955b51cae92ecfd9a4`).
- **Fiziksel Cihaz Durumu:** Telefon kullanıcı tarafından çıkarıldığı için yeni sürümün fiziksel cihaza kurulumu henüz yapılmamıştır; APK `releases/` altında yüklenmeye hazır beklemektedir.
- **Kozmetik Görseller & Mockup:** Kullanıcı tarafından sağlanacak görseller ve mockup verisi henüz verilmediğinden açık bekleyen durumdadır; slotlar hazırdır.
- **Ertelenen Otobüs Fikirleri:** Kullanıcının `Düzenlemeler.txt` notlarındaki "5 duraktan 4'ünde durma" ve "500m kısa yol cezası" fikirleri talimat doğrultusunda ertelenmiştir ve uygulanmamıştır.
