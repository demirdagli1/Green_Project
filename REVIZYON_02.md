# Yeşil Adım — kullanıcı testinden sonraki iş paketi

Bu dosya kullanıcının 30 Ekim akşamı verdiği yeni istekleri toplar. AGENT_YONETIM.md kaynak/yetki kuralları sürer; bu dosya eski ekran şartnamesinin çelişen kısımlarını geçersiz kılar. Yönetici kod yazmaz; AGY uygular. Yeni paket/SDK indirme yok. Diğer projeler salt okunur. Git commitleri yöneticide; push yok. Yeni mock-up/görseller kullanıcıdan gelecek, mevcut demo veriyi kayıpsız değiştirilebilir tut; kullanıcı verisi gelmiş gibi iddia etme.

## Aşama A — gerçek sensör akışı ve PC GM paneli

### A1 Sensör arızası gerçek veriden teşhis edilecek
Önceki düzeltme yalnız sensör durum kartının yenilenmesiydi. Kullanıcı izinler verilmişken gerçek sensörlerin hâlâ okunmadığını bildiriyor; bu ayrı açık hata.
- Native kayıt başarısı (registerListener dönüşü), EventChannel aboneliği, Android callback → Dart olay → doğrulama → kalıcı state zincirini uçtan uca incele. İzin var / listener var / gerçek event geliyor / adım sayıldı aynı şey değildir.
- Ayrı son olay zamanı/sayısı: adım sayacı ham toplamı ve delta, ivme olay/örnek sayısı ve varyans, GPS fix zamanı/doğruluğu, doğrulama kararı/ret nedeni ve pencere durumu. Bunlar PC debug/admin içinde, ana sayfada teknik teşhis yok.
- TYPE_STEP_COUNTER reboot toplamıdır; ilk örnek baseline olur, geçmiş tüm toplamı bugüne/ödüle yazma. Kısa yürüyüşün kullanıcıya sessizce kaybolmasına izin verme: doğrulanmış adım ile bekleyen doğrulama penceresini ayır; 30sn pencere kapanışı/son olay/arka plan/geçişte bekleyen adımı mükerrer yazmadan işle. Durgun telefonda yeni adım olayı gelmemesi normaldir; ivme callbackleri ile dinleme doğrulanabilir.
- GPS kapalı/kapalı mekân/henüz fix yok/approximate izin gibi durumlar açık teşhis edilir, bunları otomatik hile veya 0 hareket sayma. Aynı anda bir event aboneliği, lifecycle sonrası yeniden dinleme, tekrarlı start/stop ve native izin penceresinin pause/resume davranışı güvenli olsun. Günlük doğrulanmış puanı bozma.

### A2 İzin UX — son kullanıcı talimatı
- Uygulama ilk açılışında gerekli aktivite/konum/bildirim izinlerini yalnız bir kez iste; onboarding/ilk açılış akışında açıklamalı sırayla, kabul zorunlu değil. Sonraki açılış/resume kendiliğinden tekrar sormaz.
- Ana sayfadaki sensör/izin/"İzinleri iste"/teknik donanım teşhis kartını kaldır. Kullanıcı açıkça istemiyor. Eksik izinde ana akış çökmemeli ve sahte veri göstermemeli. Kullanıcının sonradan kendisinin açabileceği ayarlar/profil yolu olabilir; kalıcı ret için sistem ayarına yönlendirme orada.
- Mevcut kurulumun izinleri zaten verilmişse yeniden isteme. İzin-denendi işareti uygulama restartında korunur; permission durumu dinamik okunur. Testler ilk açılış/ret/kalıcı ret/yeniden açılış davranışını kapsar.

### A3 PC üzerinde GM kontrolü — yerel, gerçek cihazla aynı state
- Sadece mobil admin ekranı yetmez. PC tarayıcıdan açılan yerel panel, USB/ADB bağlı uygulamanın gerçek AppStore state'ine komut göndersin ve sonucu anında hem telefonda hem panelde göstersin. Harici hosting/Supabase gerektirmez; yerel debug aracı, yeni bir Sites projesi değil.
- Uygulanabilir yön: debug build içinde dart:io HttpServer, Android loopback'e bind; PC'ye adb forward ile erişim. Paket gerektirmeyen mevcut SDK yaklaşımı seçilebilir. 0.0.0.0/LAN'a açma, release build'de debug sunucu/GM endpointleri aktif olmasın. Oturum tokenı, yetkisiz çağrıyı ret, POST mutasyonları, istek boyutu/sayı sınırları ve idempotent komut kimliğiyle tekrarlanan istek çift ödül/ceza üretmesin. Tarayıcı cross-origin istekleri varsayılan reddedilsin. Kullanıcı verisini toplu silme işlemi varsa açık ayrı onay ve yedekleme; otomatik sıfırlama yok.
- Panel görsel olarak sade; mevcut değerler, X adım / Y streak / Z altın ekleme ve gerektiğinde açık ayrı set işlemleri; tüm mobil admin komutları ortak dispatcher üzerinden erişilebilir: transit test, araç/taksi, bisiklet/hile, hafta kapat, bildirim, demo şampiyon, aktivite/sensör test akışı, profil/durum gözlemi. Parametreli kontroller, örnekler, sonuç/ret nedeni ve olay günlüğü. Teknik cihaz ID debug panelde olabilir, profilde değil.
- Gerçek sensör akışı ile enjekte edilen DEMO olaylar açık ayrı etiketlenir. Panelden mutasyon AppStore'un aynı kurallarına/kalıcılığına girer; paralel ayrı mock state kurma. Debug düzenlemeleri gerçek sensör baseline'ını yanlışlıkla katlamasın.
- Başlatma/ADB forward/adres/token edinme/kapatma/bağlantı kesilmesi/restart sonrası tekrar bağlama README'de tek yerde anlatılsın. Çalışan paneli PC üzerinden read-state ve add/duplicate/reload kalıcılık kontrolleriyle kanıtla. Kaynak sınırı tek iş/2GBHeap/tek worker sürer.

### A4 Belirsiz cezalar ve çalışmayan demo senaryoları
- 68km/sa taksi demo butonu deterministik olmalı: yakın transit kaydı varsa normal değerlendirme doğru biçimde muaf tutabilir; jüri senaryosu ayrı açık izole DEMO ölçüm bağlamında araç koşullarını sağlar. Gerçek kullanıcı transit geçmişini silerek demo çalıştırma. Muafiyetli normal senaryoyu ayrıca test edilebilir tut.
- Bisiklet titreşim cezasını açık anlat: aktivite puanı verilmiyor, araba/taksi yolculuk sayısı +1 ve mesafe×0.192kg harcanan CO₂, Utanç Tablosuna etkisi. Altın/puan kesilmiyorsa kesiliyormuş gibi yazma. Hız reddi ile araba şüphesi cezası ayrı sonuçlar. Gerçek sezgiyi kesin taşıt kanıtı diye sunma.

## Aşama B — sıralama ve gezinme
- Lig isimlerinden oluşan üstteki yatay buton/filtre şeridini birey ve klanda tamamen kaldır.
- Satır sırası: #SIRA, PROFİL FOTOĞRAFI, İSİM/NICK (altında mevcut renk/fontla klan), LİG LOGOSU, PUAN. Logolar mevcut kod-native rozet olabilir; kullanıcı görselleri gelince değişir. Profil resmi yoksa tutarlı fallback. Büyük yazı/uzun ad/dar ekranda taşma ve yanlış avatar yok.
- Gurur/Utanç seçicisi sabit solda; tüm zamanlar/haftalık kontrolü sabit alanda. Seçim/metin uzunluğu konumu oynatmasın; her iki metin için yeterli alan veya sabit etiket + durum gösterimi. Küçük ekran için boyutlara göre kalıcı iki satır düzeni olabilir, seçimle yer değişimi olamaz.
- Klan toplam/hibrit selektörünü kaldır. Tüm klan puanları/sıralaması hibrit normalize: 0.6×toplam +0.4×50×üye ortalaması. Haftalık/tüm zamanlar seçimine uygun kaynaktan hesapla. Lig kademesiyle görüntülenen hibrit puanı karıştırma; eşikler tutarlı belirtilsin. Beşten az üyeyi sıralama dışında tut.
- İlk10 + kullanıcının/kendi klanının gerçek sırası etrafında bir üst/bir alt. Atlanan her aralık tek … satırı; aynı satır iki kere yok; gerçek rank numarası korunur. Örnek1..10 …105,106(Sen),107 … . Kullanıcı ilk10/11/son/tek satır/boş; sıralama dışı klan, olmayan profil, eşit puan ve filtre değişimleri kapsanır. Utançta kullanıcının kaydı yoksa uydurma oluşturma.
- Yeni mock veri henüz verilmedi. 100+ örneği kullanıcı vermiş gibi uydurma; pencere algoritmasını test fixture ile 120satır üzerinde sınayabilirsin. İçe aktarma kolay ve veri şemasını belgeli tut.
- Floating QR/NFC FAB kaldır. Bottom navigation kalıcı dört öğe ve sıra: QR/NFC | ANA MENÜ | SIRALAMALAR | PROFİL. Varsayılan ana menü. QR/NFC kendi sekme/ekranıdır, içerik üstünde her yerde duran buton yok. Geri tuşu davranışı ve sekmeler arası state korunur.

## Aşama C — ana sayfa ve profil
- Geçen haftanın şampiyonu henüz yoksa kullanıcıya demo etiketli birey/klan şampiyonları göster; gerçek sonuç oluşunca gerçek sonuç kazanır. Kullanıcı verisi/reset sonucunu üzerine yazma.
- Ana sayfada LigKlan+KlanSırası tek kart, LigBirey+BireySırası tek kart; uygun birey/klan sıralama sekmesine gider, kendi satırını vurgular. Dosyadaki gelecekteki kendi-klan sayfa tasarımı şimdilik bekliyor; olmayan sayfa uydurma.
- Ana sayfaya herkesin görebileceği Utanç Tablosu özeti ekle: maskeli ad+avatar, haftalık yolculuk sayısı/harcanan CO₂ ve tam tabloya geçiş. Boşsa dürüst boş durum. Tam ad sızdırma.
- Profil fotoğrafı seçme ve bio düzenleme ekle, yerel kalıcı. Paket indirmeden Android Photo Picker/ACTION_OPEN_DOCUMENT/native köprü kullanılabilir. Seçim iptali, bozuk/çok büyük görsel, döndürme ve yeniden açılış; dosyayı uygulama alanına güvenli kopyala/ölçekle, kalıcı kaybolan URI kullanma. Gereksiz tüm galeri izni isteme. Bio örn.max160karakter; Türkçe/emoji güvenli. Cihaz UUID profilde görünmesin. Fotoğraf/bio/debug state kalıcılığı eski kayıtlarla uyumlu olsun.
- Kozmetik görselleri kullanıcı sağlayacak; görüntü/çerçeve/pet asset slotları hazırlansın, görsel üretme/paket indirme yok. Mevcut text kimliklerini normal kullanıcıya göstermek yerine insan okunur ad/fallback kullan.

## Aşama D — otomatik hareket modu
- Kullanıcının bir süre tutarlı hareketiyle yürüyüş/bisiklet uygun modunu otomatik başlat. Başlangıçta ön planda çalışma sınırını açık tut; arka plan garantisi iddia etme. Manuel bisiklet ve otomatik seçim çatışmasın; kullanıcı durdurma/iptal seçeneği olsun.
- Sadece tek GPS hızına göre bisiklet/araç kararı verme. Süreli pencere+hız doğruluğu+adım değişimi+ivme, başlangıç/durma histerezisi, bekleme/durgun/ yürüyüş/ olası bisiklet durumları. Eksik sensörde sınırlı mod, muğlak taşıtta otomatik ceza yok. Otobüs/transit, trafik ışığı, kısa duruş, GPS sıçraması, zayıf GPS, telefon sallama, ardışık kısa oturum/aynı yol iki kez ödül gibi edge case'ler belgeli ve kritik kurallar testli olsun.
- Seçilen başlangıç/durma süre ve eşiklerini uygulama kararı olarak README'de belirt; bilimsel kesinlik gibi sunma. Deneme/GM panelinden saat hızlandırılmış ölçüm akışıyla deterministik doğrulanabilir olsun.

## Teslim ve çalışma ritmi
- A→B/C→D gibi anlamlı aşamaları bağımsız tamamla, tek tek dosya için yöneticiye onay sorma. Aşama bitince DURUM.md içine kısa sonuç/kanıt/sonraki iş yaz. Yönetici o aşamada yerel commit atar.
- Aynı dosyaları tekrar tekrar uzun bağlamla tarama, debug testlerinde 2–3 başarısız denemeden sonra yöntem değiştir. Kodu baştan yazma; mevcut58testi koru, yalnız değişen/önemli davranışları ekle.
- Analyze, ilgili testler, tek iş çevrimdışı APK, ADB kurulum/açılış ve gerçek PC paneli doğrulaması gereklidir. Sensör hareketini kullanıcı fiilen test etmediyse doğrulandı deme; ham callback akışını ayrı raporla. Mock veri/görseller bekleyenler teslimi engellemesin, açık bekleyen iş olarak kalsın.
