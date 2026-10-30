# Yeşil Adım — doğrulanmış durum

30 Ekim 2026, revizyon02 / Aşama A, B ve C tamamlandı. Samsung SM-A346E, Android 16 / API 36 uyumlu. Yerel commitler tutulur, push yapılmaz. Kod AGY tarafından yazılmıştır; Codex görev, inceleme ve Git yönetimini yapar.

## Revizyon02 / Aşama B ve C Tamamlananlar
- **Sıralamalar & Gezinme (Aşama B):**
  - Yatay lig buton/filtre şeridi hem Bireysel hem Klan ekranından tamamen kaldırıldı.
  - Sıralama satır düzeni kesin sıralamaya kavuşturuldu: `#RANK | AVATAR/FOTOĞRAF | İSİM/NİCK (altında klan adı) | LİG LOGOSU BADGE | PUAN`.
  - Sabit sol Gurur/Utanç seçicisi ve sağda sabit zaman (Haftalık/Tüm Zamanlar) kontrol alanı sağlandı (layout shift engellendi).
  - Klan Total/Hibrit seçicisi kaldırıldı; tüm klan sıralaması ve puanları sabit hibrit kuralına bağlandı: `0.6 * toplam + 0.4 * 50 * üye_ortalaması`. 5'ten az üyeli klanlar sıralamaya dahil edilmez.
  - Pencereleme (Windowing) algoritması (`LeaderboardWindow`): İlk 10 + kullanıcının kendi satırı ± 1 komşusu, aradaki her boşluk için tek bir `…` ellipsis, gerçek rank numaraları korunur, mükerrer satır oluşmaz. 120 satırlık test fixture ile doğrulandı. Utanç tablosunda kullanıcının kaydı yoksa sahte kayıt uydurulmaz.
  - Floating Action Button (FAB) tamamen kaldırıldı. 4 öğeli alt gezinme çubuğu (BottomNavigationBar): `[0] QR/NFC | [1] Ana Menü (varsayılan) | [2] Sıralamalar | [3] Profil`. Sistem geri tuşunda Ana Menü'ye dönüş, Ana Menü'de ise çıkış davranışı (`PopScope`) sağlandı.
- **Ana Sayfa & Profil (Aşama C):**
  - Demo şampiyon fallback: Henüz kesinleşmiş haftalık şampiyon yokken `👑 Geçen Haftanın Şampiyonları [DEMO]: ...` etiketiyle açıkça DEMO olduğu belirtilir; gerçek şampiyon oluştuğunda gerçek sonuç öncelik alır.
  - Birleşik Ana Sayfa kartları: Tek bir "Klanım & Sıram" ve "Bireysel Ligim & Sıram" kartı. Tıklanınca Sıralamalar sekmesine geçerek doğrudan ilgili listeyi açar ve kullanıcının kendi satırını mor border ile vurgular.
  - Maskeli Ana Sayfa Utanç Tablosu özeti: Maskeli isim (`Pel***`), avatar, haftalık yolculuk sayısı ve harcanan CO₂ bilgisi ile "Tam Tabloyu Gör >" geçiş linki eklendi.
  - Profil fotoğrafı ve Bio: Harici paket indirmeden Kotlin native köprüsü (`MediaStore.ACTION_PICK_IMAGES` / `ACTION_OPEN_DOCUMENT`) ile fotoğraf seçme, güvenli 1024x1024 downsampling, `filesDir` içine kalıcı kopyalama, iptal/hata/restart dayanıklılığı. Max 160 karakter bio düzenleyici (Türkçe/emoji güvenli). Normal profilde cihaz UUID gösterimi kaldırıldı.
  - Kozmetik mağazası ve envanter: Ham ID yerine insan tarafından okunabilir Türkçe adlar ve fallback etiketleri (`Varsayılan Yaprak`, `Çerçeve Yok`, vb.). Kullanıcı kozmetik görselleri henüz verilmediğinden harici paket/resim üretimi yapılmadı; mevcut asset slotları hazırlandı.
  - PC GM paneli: Durum JSON sözleşmesine `bio` ve `photoPath` alanları eklendi; `set_bio` komutu eklendi.

## Kanıt ve Sınırlar
- **Statik Kod Analizi:** `dart analyze` ile **0 issue** (hatasız ve uyarısız).
- **Test Kapsamı:** **94 / 94 test geçti** (`rules_test`, `store_test`, `gm_panel_test`, `ui_flow_test`, `leaderboard_window_test`, `phase_b_c_test`).
- **APK Derlemesi:** Tek-worker / 2GB JVM Heap ile tamamen çevrimdışı `./gradlew assembleDebug --offline --no-daemon --max-workers=1` başarıyla tamamlandı (13s), `build/app/outputs/flutter-apk/app-debug.apk` üretildi.
- **Fiziksel Cihaz Kurulumu & Durumu:** Samsung SM-A346E (Android 16 / API 36) üzerinde önceki sürüm çalışır durumdadır. Cihaz USB bağlantısı geçici olarak ayrıldığında `adb install -r` için APK hazırdır.
- **Kozmetik Görseller:** Kullanıcı tarafından sağlanacak görseller beklenmektedir.
- **Aşama D (Otomatik Aktivite & Süreli Ölçümler):** Bir sonraki aşamada ele alınacaktır; mevcut mimariyi bozmadan eklenecektir.

## Araçlar ve Çalışma Ortamı
Flutter/JDK17/Pub cache: `/home/girdap/Masaüstü/WordMaster/.tools/`. Android SDK: `/home/girdap/Masaüstü/itiraf/.tools/android-sdk`.
Flutter için `FLUTTER_NO_VERSION_CHECK=true CI=true`, offline testte `--no-pub --concurrency=1`. Gradle: `./gradlew assembleDebug --offline --no-daemon --max-workers=1 -Dorg.gradle.jvmargs="-Xmx2048m"`. Yeni paket indirme veya dış ağ çağrısı yapılmamıştır.
