# Devam noktası — 31 Ekim 2026

Bu dosya güncel kayıttır. Eski raporlar `docs/arsiv/` içindedir; hepsini tekrar okumak gerekmez. Kullanıcı son olarak commit/checkpoint ve bağlamı yenileme istedi; QR/NFC isteğini yeni bağlamda yeniden verecek.

## Kullanıcıyla çalışma
- Codex yönetir; ürün/test/SQL kodunu AGY Gemini 3.8 Flash High yazar. Tokenı koru, kısa ve sade konuş. Git yerel; **push yok**. Ayrıntılı kurallar: [AGENT_YONETIM.md](AGENT_YONETIM.md).
- İndirme yok; kurulu Flutter/JDK/SDK ve çevrimdışı önbellekler kullanılır. Tek ağır test/derleme, Gradle tek worker/2 GB heap.
- Telefonun elle testini kullanıcı yapar. Yeni APK bu oturumda cihazlara otomatik kurulmadı. Gerçek yürüyüş/otobüs ve üç telefonun ekranında canlı yenilenme doğrulanmış sayılmaz.
- Kullanıcının `Düzenlemeler.txt` değişiklikleri korunuyor, yönetici commitine katılmadı. Kullanılmayan birleşik logo ve pet MP4 dosyası da olduğu gibi kaldı.

## Ana sürümde yapılanlar
- Verilen mock veriler, bireysel/klan lig logoları ve launcher logosu yerleştirildi. Profil fotoğrafı/bio ve satın alınıp kuşanılan Bit-Bee / Ozon Perisi görselleri eklendi.
- Sıralamalar ilk 10 ve kullanıcının komşularını gösterir. Klan utanç sıralaması, klan detay sayfası/gerçek rol alanı ve ana ekran bağlantıları düzenlendi.
- Utanç mesajı: 50 görünen karakter, 10 altın, gönderen başına İstanbul takvim gününde bir mesaj. Sunucu kota/harcama ve admin kota sıfırlama yolları var. Gerçek arka plan push / ulaşım operatörü entegrasyonu yapılmış sayılmaz.
- Supabase oturum/outbox/yeniden bağlanma ve başka kullanıcı güncellemeleri üzerinde düzeltmeler yapıldı. GM paneli artık sunucu kullanıcılarını seçerek işlem yapıyor; telefon kablosu gerekmiyor.

## Kanıtlar ve APK
- AGY son Dart analizi: 0 issue. Otomatik test günlüğü: **132/132**, `evidence/rev03_unit_tests.log`.
- İki bağımsız HTTP oturumuyla A'nın adım kaydından kazandığı **0 → 5 puan** B'nin ortak sıralamasında görüldü. Yetkisiz GM ve özel veri erişim ret kontrolleri var: `evidence/rev03_live_two_sessions.log`.
- WebSocket kanalı bağlantısı görüldü; bu, gerçek değişiklik olayının üç fiziksel cihaz ekranına ulaştığı kanıtı değildir.
- APK: [releases/YeSilAdim-debug.apk](releases/YeSilAdim-debug.apk), 173.965.301 bayt. Dosya doğrulaması root tarafından geçti.
- SHA-256: `1f09907ec13f3f31ba3ddc58721a7eb331546cef309e658c908290142827d19b`.
- Son değişiklikler yalnız SQL/test/belgelerde olduğundan APK sebepsiz yeniden derlenmedi.

## Canlı sunucu: son kesin durum
- Proje `fhaxxraibydsjikxacbb`, Green_Project, eu-central-1; 0 $/ay kullanıcı tarafından onaylandı. Anonymous Auth çalışıyor. Başka projelere dokunulmadı.
- Uygulanan migration'lar: `green_project_initial_schema_safe`, `green_project_revision_03`, `green_project_delivery_fixes`, `green_project_transit_input_validation`, `green_project_transit_schema_fix`.
- 08 sürümündeki hatalı alan adları 09 ile düzeltildi. 09 önce `supabase/preflight_delivery.sql` ile açık BEGIN/ROLLBACK içinde **başarıyla** test edildi, ardından uygulandı. Sonrasında `supabase/verification_rev08.sql` de **başarıyla** çalıştı. Testler kalıcı kullanıcı mutasyonu bırakmadı.
- Son doğrulama; boş/yanlış/wildcard durak kodları, 44:59 ret / 45:00 kabul, gerçek seed URI/NFC eşleşmeleri ve yetkili GM/audit yollarını kapsar. Testteki küsurat beklentisi DB hassasiyetine uyarlandı; uydurma durak kodları gerçek seed verileriyle değiştirildi.
- Son güvenlik danışmanı: 0 ERROR, 14 WARN. Definer RPC/anonim politika ve parola ayarı uyarıları mevcut; bütün uyarılar giderildi denmemeli.
- Dağıtılmış migration'ları tekrar yazıp uygulama. `supabase/drafts/07_revizyon_03_fix.sql` eski, **uygulanmamış taslaktır**; migration dizininden ayrıldı.

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

## Yeniden verilecek istek / kalanlar
- Eski kullanıcı ifadesi: “Bottom nav-bar da bulunan qr/nfc sayfası içerisinde bulunan QR/NFC sekmesini komple kaldıralım. Zaten filtreleme yerine koyacağız.”
- Bu, yalnız iç sekmenin kaldırılması olarak yorumlandı; okutma işlevi bırakıldı. Kullanıcı bunun kapsamını sorguladı. Yeni bir seçim sorusu istemedi; promptu yeniden vereceğini söyledi. **Aynı soruyu tekrarlama; yeni promptu bekle.**
- Kullanıcı yeni APK'yı telefonlarda elle test edecek; geri bildirimler sonraki iş paketidir. Gerçek transit QR/NFC altyapısı ve arka plan push hazır değildir.

## Belgeler ve commitler
- [Basit sunum](docs/SUNUM_CALISMA_REHBERI.md), [algoritma ve mimari dersi](docs/ALGORITMALAR_VE_MIMARI.md), [kullanım / panel](docs/KULLANIM.md).
- Kök yalnız README, DURUM ve AGENT_YONETIM MD'lerini tutar; kaynak isterler `docs/isterler/`, geçmiş notlar `docs/arsiv/` altında.
- Önemli ana commitler: `be495d3` Supabase başlangıcı; `cda28f9` Revizyon 03 arayüz taslağı; `86ad6c0` incelenen bulut/GM checkpoint; `d3c41fd` ortak puan ve GM giriş düzeltmeleri. Son checkpoint için `git log --oneline -n 5`.
- Tüm AGY işleri bu checkpoint'te durmuş/tamamlanmıştır; açık tek yardımcı süreç yerel GM HTTP sunucusu olabilir. Devam için bu dosya ve kullanıcının yeni promptu yeterlidir.
