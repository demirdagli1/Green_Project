# Devam noktası — 31 Ekim 2026

Bu dosya güncel kayıttır. Eski raporlar `docs/arsiv/` içindedir; hepsini tekrar okumak gerekmez.

## Kullanıcıyla çalışma
- Codex yönetir; ürün/test/SQL kodunu AGY Gemini 3.8 Flash High yazar. Tokenı koru, kısa ve sade konuş. Git yerel; **push yok**. Ayrıntılı kurallar: [AGENT_YONETIM.md](AGENT_YONETIM.md).
- İndirme yok; kurulu Flutter/JDK/SDK ve çevrimdışı önbellekler kullanılır. Tek ağır test/derleme, Gradle tek worker/2 GB heap.
- Kullanıcının `Düzenlemeler.txt` değişiklikleri korunuyor, yönetici commitine katılmadı.
- Root bağlı cihaza `adb install -r releases/YeSilAdim-debug.apk` ile kurulum yapacaktır; AGY doğrudan cihaz kurulumu yapmaz.

## Son tamamlanan teslim paketi (QR/NFC UI Kaldırma & 3 Sekmeli Shell)
- **Kullanıcı düzeltmesi uygulandı:** Kullanıcıya açık QR/NFC okutma arayüzü tamamen kaldırıldı. Bottom navigation yalnız 3 öğe ve 3 sayfadan oluşur:
  1. **Ana Sayfa** (Index 0, varsayılan başlangıç)
  2. **Sıralamalar** (Index 1, kategori/utanç/vurgu geçişleri)
  3. **Profil** (Index 2, mağaza ve envanter)
- `MainShell` sayfa yığını, seçili indeks, geri tuşu (PopScope index 0'da çıkış, diğerlerinde Ana Sayfaya dönüş) ve sekme geçiş callbackleri 3 sekmeye uyarlandı.
- Kullanılmayan `lib/screens/transit_bike/qr_nfc_bike_modal.dart` ekranı arayüzden temizlendi. Kamera/NFC native donanım köprüleri ve Supabase geçmiş migration kayıtları tarihsel bütünlük için körlemesine silinmedi; yalnızca kullanıcı arayüzünde okutma girişi bırakılmadı.
- **Bisiklet işlevi korundu:** `HomeScreen` üzerindeki `AutoMotionEngine` otomatik bisiklet algılama kartı (hız, mesafe, maks hız metrikleri, 'Bitir & Kaydet' ve 'İptal' aksiyonları) eksiksiz çalışmaktadır. `AppStore.cancelBike()` metodu eklendi.

## 500m Kısa Otobüs Cezası Durumu (İnceleme & Net Bildirim)
- **Canlıya sahte/erken aktivasyon yapılmadı:**
  - Kullanıcı arayüzünden QR/NFC okutma tamamen kaldırılmıştır; durak kodu tek başına mesafe kanıtı değildir.
  - Gerçek 2 katmanlı otomatik otobüs sensör füzyon motoru `.worktrees/automatic-bus` dalında geliştirme aşamasındadır ve ana sunucuda `rpc_record_bus_trip` migration 07 ile güvenli **dormant** (etkisiz) durumdadır.
  - İstemci tarafında `AutoTransportClassifierService` içinde 0 < mesafe <= 500m için -3 puan cezası (`DetectedActivityType.shortBusPenalty`) kuralı ve birim testleri hazırdır; ancak arkasında gerçek doğrulanmış otomatik yolculuk akışı olmadan canlı veritabanında sahte/keyfi ceza altyapısı **bilerek etkinleştirilmemiştir**.

## Kanıtlar, Testler ve APK
- **Dart Analizi:** `dart analyze` ➔ **No issues found!** (0 hata, 0 uyarı).
- **Otomatik Testler:** Çevrimdışı, `--no-pub --concurrency=1` ile **134/134 test BAŞARIYLA GEÇTİ** (`All tests passed!`). 3 sekmeli MainShell ve UI akış testleri güncellendi.
- **Gradle Derlemesi:** `android/local.properties` Türkçe karakter yolu Java Properties standardına uygun olarak `Masa\u00fcst\u00fc` biçimine getirildi. `./gradlew assembleDebug --offline --no-daemon --max-workers=1` ile tek worker olarak **14 saniyede BUILD SUCCESSFUL** tamamlandı.
- **APK Dosyası:** [releases/YeSilAdim-debug.apk](releases/YeSilAdim-debug.apk), **173.957.546 bayt**.
- **SHA-256:** `700b2a66a1726d45f177af58eae1167d6dc67d1fceece8711a56708d95d1498a`.
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
