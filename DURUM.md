# Devam noktası — 31 Ekim 2026

Bu dosya güncel kayıttır. Eski raporlar `docs/arsiv/` içindedir; hepsini tekrar okumak gerekmez.

## Kullanıcıyla çalışma
- Codex yönetir; ürün/test/SQL kodunu AGY Gemini 3.8 Flash High yazar. Tokenı koru, kısa ve sade konuş. Git yerel; **push yok**. Ayrıntılı kurallar: [AGENT_YONETIM.md](AGENT_YONETIM.md).
- İndirme yok; kurulu Flutter/JDK/SDK ve çevrimdışı önbellekler kullanılır. Tek ağır test/derleme, Gradle tek worker/2 GB heap.
- Telefonun elle testini kullanıcı yapar. Yeni APK bu oturumda cihazlara otomatik kurulmadı. Gerçek yürüyüş/otobüs ve üç telefonun ekranında canlı yenilenme doğrulanmış sayılmaz.
- Kullanıcının `Düzenlemeler.txt` değişiklikleri korunuyor, yönetici commitine katılmadı. Kullanılmayan birleşik logo ve pet MP4 dosyası da olduğu gibi kaldı.

## Ana sürümde yapılanlar ve güncel iş paketi
- Verilen mock veriler, bireysel/klan lig logoları ve launcher logosu yerleştirildi. Profil fotoğrafı/bio ve satın alınıp kuşanılan Bit-Bee / Ozon Perisi görselleri eklendi (profil fotoğrafının sağında ve mağaza slotlarında şeffaf PNG).
- Sıralamalar ilk 10 ve kullanıcının komşularını gösterir. Klan utanç sıralaması, klan detay sayfası/gerçek rol alanı ve ana ekran bağlantıları düzenlendi:
  - Klan hiyerarşisi indeks puanına göre sahte liderlik üretmez, doğrudan sunucu ve modeldeki `clanRole` verisinden ('leader', 'elder', 'member') beslenir.
  - Klanı olmayan kullanıcılar için ana ekranda "Kül Birliği • 0 üye" yerine "Klansız" ve "Klan sıralamasını gör" net gösterimi sağlandı.
  - Klan utanç satırına tıklandığında hem doğrudan klan üyesine utanç mesajı gönderme (üyeler arasından hedef seçimi ile) hem de klan detay/hiyerarşi sayfasını açma seçenekleri modal olarak sunuldu.
- Utanç mesajı: 50 görünen karakter (`.characters.length`), 10 altın, gönderen başına İstanbul takvim gününde bir mesaj. Sunucu kota/harcama ve admin kota sıfırlama yolları var.
- QR/NFC sekmesi: `lib/screens/transit_bike/qr_nfc_bike_modal.dart` içinde iç sekme (TabBar / TabBarView) zaten bulunmadığı ve tek `ListView` akışında toplu taşıma ve bisiklet bölümleri yer aldığı teyit edildi.
- Supabase oturum/outbox senkronu: `update_bio` işleminde ağ/bağlantı hatasında outbox öğesini sessizce silen açık giderildi; başarısız istekler kuyrukta retry ve backoff ile saklanır. Realtime `admin_notifications_log` aboneliği `target_user_id` filtresine tabi tutuldu.
- Evrensel GM Paneli: PC tarayıcı panelinde (`tools/universal_gm/index.html`) seçili kullanıcıya tek basışla test uyarısı ileten "🚨 Rahatsız Edici Bildirim Gönder" düğmesi ve `sendAlertNotification()` işlevi eklendi. Yerel `CommandDispatcher` köprüsüne `send_alert_notification` eklendi; native köprü `showNotification` callback çağrısı ve `DEFAULT_ALL` (ses/titreşim) tetikleyicisi entegre edildi.
- Sunucu Migration 10: `supabase/migrations/10_gm_alert_notification.sql` ve açık `BEGIN/ROLLBACK` preflight doğrulama dosyası `supabase/preflight_alert_notification.sql` root tarafından rollback preflight ile doğrulandı ve canlıya uygulandı.

## Kanıtlar ve APK
- AGY son Dart analizi: 0 issue (`No issues found!`).
- Otomatik test günlüğü: Önceki **132/132** (`evidence/rev03_unit_tests.log`) korundu; güncel outbox `update_bio` hata koruması ve `send_alert_notification` yerel köprü testleri dahil **27/27** geçti: `evidence/rev03_alert_and_outbox_tests.log`.
- İki bağımsız HTTP oturumuyla A'nın adım kaydından kazandığı **0 → 5 puan** B'nin ortak sıralamasında görüldü. Yetkisiz GM ve özel veri erişim ret kontrolleri var: `evidence/rev03_live_two_sessions.log`.
- WebSocket kanalı bağlantısı görüldü; bu, gerçek değişiklik olayının üç fiziksel cihaz ekranına ulaştığı kanıtı değildir. Testlerde gerçek OS ses/titreşimi değil, native köprü callback çağrısı doğrulanmıştır.
- APK: [releases/YeSilAdim-debug.apk](releases/YeSilAdim-debug.apk), 173.966.529 bayt. Dosya doğrulaması root tarafından geçti.
- SHA-256: `83745a80601ef58529a1ae7e0fede057ef94f5fbaee302051fdb12d6bae3bc89`.
- Yeni APK çevrimdışı, tek worker ile derlendi: BUILD SUCCESSFUL (15 saniye). Günlük: `evidence/quick_delivery_build.log`. Dosya SHA-256 kontrolü geçti; telefonlara kurulmadı.

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

## Kalan riskler ve sonraki adımlar
- Gerçek transit QR/NFC altyapısı ve arka plan push FCM hazır değildir. Arka plan FCM push servisi bulunmadığından uygulama kapalıyken teslim garantisi verilemez; ön plandayken veya açıkken Realtime + yerel bildirim köprüsü çalışır. Testlerde gerçek OS ses/titreşimi değil, Android köprü callback çağrısı doğrulanmıştır.
- Kullanıcı yeni APK'yı telefonlarda elle test edecek; geri bildirimler sonraki iş paketidir.

## Belgeler ve commitler
- [Basit sunum](docs/SUNUM_CALISMA_REHBERI.md), [algoritma ve mimari dersi](docs/ALGORITMALAR_VE_MIMARI.md), [kullanım / panel](docs/KULLANIM.md).
- Kök yalnız README, DURUM ve AGENT_YONETIM MD'lerini tutar; kaynak isterler `docs/isterler/`, geçmiş notlar `docs/arsiv/` altında.
- Önemli ana commitler: `be495d3` Supabase başlangıcı; `cda28f9` Revizyon 03 arayüz taslağı; `86ad6c0` incelenen bulut/GM checkpoint; `d3c41fd` ortak puan ve GM giriş düzeltmeleri. Bu tur uygulama commiti: `761a58c`. Son checkpoint için `git log --oneline -n 5`.
- Tüm AGY işleri bu checkpoint'te durmuş/tamamlanmıştır; açık tek yardımcı süreç yerel GM HTTP sunucusu olabilir. Deadline nedeniyle yeni özellik açılmadı; otobüs sonraki pakette. Devam için bu dosya ve kullanıcının geri bildirimi yeterlidir.
