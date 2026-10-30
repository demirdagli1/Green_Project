# Yeşil Adım — Sürüm Notları (Aşama B, C, D)

- **Tarih:** 30 Ekim 2026
- **Derleme Tipi:** Debug (Tamamen Çevrimdışı, 1 worker, 2GB JVM Heap)
- **Dosya Adı:** `YeSilAdim-debug.apk`
- **Dosya Boyutu:** ~147 MB
- **SHA-256 Özeti:** `d7a2359c58a3260c7449be7622e69026db6e1ea292d3f4955b51cae92ecfd9a4`
- **Hedef Cihaz & Platform:** Samsung SM-A346E (Android 16 / API 36)

---

## 🌟 Eklenen ve Doğrulanan Özellikler

### 1. Aşama B (Sıralamalar & Gezinme)
- **Lig Buton Şeridi Kaldırıldı:** Yatay lig filtresi şeridi kaldırıldı.
- **Kesin Satır Düzeni:** `#RANK | AVATAR/FOTOĞRAF | İSİM/NİCK (altında klan adı) | LİG LOGOSU | PUAN`.
- **Sabit Kontroller:** Sol Gurur/Utanç ve sağ Haftalık/Tüm Zamanlar seçicileri sabitlendi.
- **Yalnızca Hibrit Klan Puanı:** `0.6 * toplam + 0.4 * 50 * üye_ortalaması` (<5 üye hariç).
- **Pencereleme Algoritması (`LeaderboardWindow`):** Top 10 + kendi satırı ± 1 komşusu, tek `…` ellipsis, gerçek rank sırası, 120 satırlık test fixture ile doğrulandı.
- **4 Öğeli Alt Gezinme:** `QR/NFC (0) | Ana Menü (1, varsayılan) | Sıralamalar (2) | Profil (3)`. Floating FAB kaldırıldı; sistem geri tuşu Ana Menü'ye döner.

### 2. Aşama C (Ana Sayfa & Profil)
- **Demo Şampiyon Fallback:** Kesinleşmiş sonuç yokken açık `[DEMO]` etiketi fallback gösterilir.
- **Birleşik Kartlar:** Ana sayfada tekil "Klanım & Sıram" ve "Bireysel Ligim & Sıram" kartları tıklandığında Sıralamalar sekmesini açar ve kendi satırını mor border ile vurgular.
- **Maskeli Utanç Özeti:** Ana sayfada maskeli isim (`Pel***`), avatar, haftalık yolculuk ve harcanan CO₂ bilgisi ile tam tabloya doğrudan geçiş linki.
- **Profil Fotoğrafı & Bio:** Android Photo Picker / OpenDocument native köprüsü (`MainActivity.kt`) üzerinden 1024x1024 downsampling ile yerel dosya alanına güvenli kopyalama, kalıcılık ve iptal/bozuk dosya dayanıklılığı. Max 160 karakter bio düzenleyici. Normal profilden UUID gizlendi.
- **Kozmetik Slotları:** Ham ID yerine insan tarafından okunabilir etiketler ve fallback desteği.

### 3. Aşama D (Otomatik Hareket Modu)
- **Aktivite Durum Motoru (`AutoMotionEngine`):** `idle`, `walking`, `potentialBike`, `cycling`, `limitedMode` durum makinesi.
- **Başlama Histerezisi:** Tekil hız okumasına güvenilmez. En az 10 saniye ve 3 ardışık GPS fix boyunca 9-45 km/sa hız, düşük adım artışı ve uygun ivme varyansı doğrulanmadan sürüş başlatılmaz.
- **Trafik Işığı & Kısa Duraklama Toleransı:** Kırmızı ışıkta hız 0 km/sa'ye düştüğünde sürüş hemen sonlandırılmaz; 45 saniyeye kadar tolerans tanınır. 45 sn hareketsiz kalırsa sürüş otomatik olarak tamamlanır.
- **Manuel Sürüş Önceliği:** Kullanıcı manuel bisiklet başlattığında otomatik motor pasif izlemede kalır, sürüşü bozmaz.
- **Kullanıcı Kontrolü:** Ana sayfada dinamik aktif sürüş kartı üzerinden "Bitir & Kaydet" veya cezasız "İptal Et" seçenekleri.
- **Çift Ödüllendirme Engeli (Anti Double-Dipping):** Bisiklet sürüşü esnasındaki pedal adımları günlük 1000 adım bonusuna katılmaz; aynı yol tekil `tripId` ile tek bir kaynaktan ödüllendirilir.
- **Eksik GPS / Zayıf Sensör Güvenliği:** GPS yoksa veya doğruluk > 30m ise sınırlı moda geçer; muğlak taşıtta asla otomatik ceza vermez.
- **GM Paneli Simülasyonu:** `auto_motion_simulate`, `auto_motion_finish`, `auto_motion_cancel` komut sözleşmesi.

---

## 🧪 Doğrulama ve Test Raporu
- **Statik Kod Analizi:** `dart analyze` ➔ **0 issue (Hatasız ve Uyarısız)**
- **Bağımsız Son Derleme:** Çevrimdışı tek worker / 2 GB Heap ile **12 saniyede başarılı**; `evidence/final_build.log`. Teslim dosyası bu son build çıktısından kopyalandı ve SHA-256 doğrulandı.
- **Otomasyonlu Testler:** `flutter test --no-pub --concurrency=1` ➔ **103 / 103 test BAŞARILI**
  - `rules_test.dart`: 20 test
  - `store_test.dart`: 32 test
  - `gm_panel_test.dart`: 13 test
  - `ui_flow_test.dart`: 6 test
  - `leaderboard_window_test.dart`: 12 test
  - `phase_b_c_test.dart`: 11 test
  - `phase_d_test.dart`: 9 test

---

## ⚠️ Sınırlar ve Açık Bekleyenler
1. **Fiziksel Cihaz Doğrulaması:** Kullanıcı telefonu USB kablosundan çıkardığından, yeni APK'nın fiziksel cihaza kurulumu (`adb install -r releases/YeSilAdim-debug.apk`) cihaz yeniden bağlandığında yapılacaktır.
2. **Kullanıcı Kozmetik Görselleri & Mockup:** Kullanıcı tarafından sağlanacak görseller henüz verilmemiştir; slotlar ve insan okunur fallback adları hazırdır.
3. **Ertelenen Otobüs Fikirleri:** Kullanıcının `Düzenlemeler.txt` içinde sonradan belirttiği "5 duraktan 4'ünde durma" ve "500m kısa yol cezası" fikirleri talimat gereği ertelenmiştir, uygulanmamıştır.
4. **Gerçek Sensör ve Fotoğraf Testi:** İvme/GPS callbackleri önceki cihaz sürümünde görüldü; fiziksel yürüyüş, yeni otomatik mod ve fotoğraf seçicinin yeni APK üzerindeki saha testi bekliyor. Otomatik mod yalnız uygulama ön plandayken çalışır; eşikler uygulama kararıdır, taşıt türünün kesin kanıtı değildir.
5. **Bağlantı Sınırları:** Canlı Supabase/cihazlar arası Realtime ve kamera ile QR tarama henüz yoktur. Transit akışı manuel kod/NFC/demo içindir; fiziksel NFC etiketiyle gerçek biniş doğrulaması yapılmadı. Veri ihtiyacı `TOPLU_TASIMA_ARASTIRMA.md` içinde.
