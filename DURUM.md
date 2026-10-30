# Yeşil Adım — doğrulanmış durum

30 Ekim 2026, revizyon02/A. Samsung SM-A346E, Android16/API36. Yerel commitler tutulur, push yapılmaz. Kod AGY tarafından yazılmıştır; Codex görev, inceleme ve Git yönetimini yapar.

## Revizyon02 / A tamamlananlar
- Gerçek native→Dart sensör olayları ve kayıt sonucu telemetrisi: ham adım/baseline/bekleyen pencere, ivme örnekleri/varyans, GPS doğruluğu/son fix, doğrulama kararı. Kısa yürüyüş son olayında pencerenin sessizce kaybolmasını önleyen zamanlayıcı eklendi.
- İlk açılışta tek izin-deneme akışı; ana sayfadaki teknik sensör/izin kartı kaldırıldı. Sonradan izin yönetimi ve teknik teşhis profil/debug tarafında.
- PC GM paneli aynı telefon AppStore verisini yönetir: parametreli adım/streak/altın ekleme/ayarlama ve mevcut admin senaryoları. Yerel loopback, release engeli, token doğrulama, tam origin kontrolü, streaming64KB sınırı ve tekrarlı komut/çakışma kontrolü mevcut.
- 68km/sa taksi demosu izole DEMO bağlamında deterministik çalışır; gerçek değerlendirmede transit muafiyeti korunur. Bisiklet reddi ve araba/taksi cezasının sayaç/CO₂ etkileri ayrı açıklanır.

## Kanıt ve sınırlar
- [Test kaydı](evidence/revision_a_manager_tests.log):71test geçti. [Önceki58test](evidence/test_all.log) ilk sürüm kaydıdır; güncel sayı ile karıştırılmamalı.
- AşamaA çevrimdışı tek-worker/2GBHeap APK derlendi ve profil silinmeden cihaza kuruldu. Alt ajanın build çıktısı23s başarı bildirdi; önceki [build kaydı](evidence/build_debug_latest.log) ilk sürümdür.
- PC üzerinden canlı testte +334adım bir kez uygulandı; aynıID tekrarı duplicate oldu; aynıID farklıpayload reddedildi. Ayrıca +150DEMOaltın ve bir DEMOtaksi olayı test için uygulandı. Kullanıcının profili sıfırlanmadı.
- Gerçek cihazda ivme callbackleri ve GPS fixleri görüldü. Adım sayacının ham ilk olayı/baseline görüldü. **Fiziksel yürüyüş henüz denenmedi:** kullanıcı telefonu kısaUSBkablosuyla bağlı tuttuğundan yapılamıyor. İzin/dinleyici mevcut olması tüm yürüyüşlerin doğru sayıldığını kanıtlamaz.
- Arka planda/uygulama kapalıyken kesintisiz izleme garantisi yok. KameraQR taraması ve canlıSupabase/cihazlar arasıRealtime eksik; mevcut transit girişi manuel/NFC/demo bağlamıdır. Fiziksel NFCetiketiyle biniş doğrulaması yapılmadı.
- HamGMçıktıları koordinat/UUID/token içerebildiğinden Git'e eklenmez. [Bug kaydı](BUG_TAKIP.md), [revizyon sözleşmesi](REVIZYON_02.md), [toplu taşıma veri listesi](TOPLU_TASIMA_ARASTIRMA.md).

## PC GM paneline erişim
1. Telefon USB/ADB ile bağlı ve uygulama açık olmalı. `adb forward tcp:8088 tcp:8088` çalıştır.
2. Profil→Jüri/Admin içindeki GMkartından tokenı kopyala. Adres: `http://127.0.0.1:8088/?token=<GM_TOKEN>` . Tokenı Git'e/mesajlara kaydetme; uygulamadaki güncel değeri kullan.
3. Panel telefonun state'ini okur; komutlar DEMO etiketiyle aynı kalıcı state'i değiştirir. Yeniden başlatma/USBkopması sonrası uygulamayı açıp forwardı yeniden kurmak gerekebilir. Yalnız debug geliştirme ortamıdır; LAN/uzak internet servisi değildir.

## Devam eden paket
- B: sıralama satırları/top10±komşular, sabit seçiciler, hibrit-only klan puanı, dörtöğeli bottomnavigation.
- C: demoşampiyon, birleşik lig/sıra kartları, ana sayfa utançözeti, fotoğraf/bio ve profil sadeleştirmesi.
- D: süreli ölçümlerle otomatik yürüyüş/bisiklet; yanlış ceza vermeyen sınırlamalar ve durum geçişi testleri.
- Kullanıcının mock-upverisi ve kozmetik görselleri henüz bekleniyor. Sağlanmadan kullanıcıverisi gelmiş gibi demo üretme.

## Araçlar
Flutter/JDK17/Pubcache: `/home/girdap/Masaüstü/WordMaster/.tools/`. AndroidSDK: `/home/girdap/Masaüstü/itiraf/.tools/android-sdk`.
Flutter için `FLUTTER_NO_VERSION_CHECK=true CI=true`, Pubişlemlerinde offline; testte `--no-pub --concurrency=1`. Gradle: `./gradlew assembleDebug --offline --no-daemon --max-workers=1`. Yeniindirme/güncelleme yok.
