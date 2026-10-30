# Yeşil Adım — görev sözleşmesi

## Yetki ve sorumluluk
- Kullanıcı: Codex yalnızca yönetir, kod yazmaz. Uygulama, test ve yapılandırma kodunu AGY alt ajanı yazar. İlk model gemini-3.8-flash-low; yönetici kalite gerekçesiyle medium veya Claude'a yükseltebilir. Hermes/Deepseek bu aşamada kullanılmaz.
- Asıl kapsam: codex_flutter_android_yonergesi.md ve Şablon.png. Kullanıcının son talimatları üstündür. Önce işlev ve yerleşim; görsel cilalama sonra. Gereksiz animasyon/illüstrasyon üretme.
- Yalnızca Green_Project içinde değişiklik yap. Diğer projeleri SDK/önbellek/yapılandırma keşfi için salt okunur incele; kaynaklarını, kimlik bilgilerini veya kullanıcı verilerini kopyalama. Sistem ayarlarını değiştirme, cihazı sıfırlama, başka uygulama kaldırma.
- İnternet yavaş: SDK, paket, Gradle veya araç indirme/güncelleme YAPMA. Mevcut Flutter ve Android araçlarını bul, çevrimdışı önbelleklerden yararlan. Eksik bağımlılıkları somut adıyla raporla; sessizce kapsamdan düşürme. Ağ erişimi kullanan komutları offline seçenekleriyle sınırla.
- Flutter sürüm sorgusu bile otomatik git fetch başlatabilir: tüm Flutter komutlarında FLUTTER_NO_VERSION_CHECK=true ve CI=true kullan; pub için --offline, create için --no-pub kullan. Gradle çözümlemelerini offline yap. Yönetici ilk --version sorgusunun uzayan git uzak bağlantısını durdurdu.
- Bulunan Flutter: /home/girdap/Masaüstü/WordMaster/.tools/flutter/bin/flutter. Ek pub önbelleği: /home/girdap/Masaüstü/WordMaster/.tools/pub-cache. Önceki projeler: WordMaster, itiraf, music-player. ADB: R6CWB01ASJT Samsung SM_A346E. Flutter PATH'te olmaması kurulu olmadığı anlamına gelmez.

## Çalışma biçimi ve teslim
- Geniş işi bağımsız yürüt; yöneticiye her dosya için soru sorma. Önce araç/önbellek envanteri, sonra işlevsel Android sürümü, sonra anlamlı testler ve fiziksel cihaz kontrolü. Kaliteyi bozan bir engelde durumu ve seçenekleri bildir.
- Token tasarrufu: bu dosyayı ve asıl şartnameyi oku; tekrar tekrar uzun plan anlatma. Sonuçları DURUM.md içinde kısa tut: tamamlananlar, doğrulama komutları/sonuçları, gerçek/demo/eksik özellik ayrımı, engeller, sonraki adım. Özetleri en fazla birkaç paragraf tut, büyük logları ayrı dosyaya yaz.
- Kullanıcı yerel ara commitler istedi: Git yönetimini Codex yapar. Remote https://github.com/demirdagli1/Green_Project; kesinlikle push yok. Alt ajan commit/reset/checkout yapmasın; uygulama işine devam etsin.
- Tamamlandı demek için analyze, iş kurallarına yönelik testler, offline APK derlemesi ve ADB açılış kontrolü kanıtı gerekir. Yapılamayan her kontrolü açıkça belirt. Sadece ekran çizip bütün şartname tamamlandı deme.
- Mevcut cihazda bu projeye özgü paket kimliğiyle kurulum/açılış yapabilirsin. İzinleri ve gerçek sensörleri test et; QR/NFC fiziksel materyal yoksa test edildi iddiasında bulunma. Ekran görüntüsü ve odaklı hata logu ile kanıt bırak.

## Ürün kararları ve sınırlar
- İlk sürüm tüm ana ekranların tutarlı yerleşimini, gezinmeyi, onboarding, yerel kalıcılık, sıralama, mağaza ve admin/demo akışlarını kapsar. Demo işlemlerini görünür biçimde etiketle; gerçek sensör ve backend sonuçlarıyla karıştırma.
- Supabase bilgisi bulunmazsa çalışan yerel kalıcı demo sun. Ağ hatasında state kaybetme, çift ödül yaratma. Gerçek senkronizasyon ve cihazlar arası Realtime test edilmediyse doğrulanmadı de.
- E-posta/OTP ekranı yok. Yerel UUID güvenli sunucu kimliği değildir; istemciye açık tam yetkili admin/haftalık reset API'si veya service_role anahtarı koyma. Canlı backend için sunucuda yetkilendirme gerekir. Demo admin yetkisi yerel veriye uygulanabilir.
- Supabase uygulanacaksa /home/girdap/.codex/plugins/cache/openai-curated-remote/supabase/1.0.0/skills/supabase/SKILL.md talimatlarını oku; güncel API'yi mevcut yerel belgelerden doğrula, ağ gerektiren doğrulama yoksa sınırlamayı yaz. RLS ve atomik/idempotent ödül/harcama/reset işlemleri şarttır; uzaktaki projeyi kendiliğinden değiştirme.
- Şartnamedeki km/s ifadesini km/sa olarak yorumla. Sensör eşikleri taşıt türünü kesin kanıtlamaz: GPS belirsizliği veya veri eksikliği otomatik suçlama yaratmamalı. Demo kesin sonuçlarını ve gerçek ölçüm sezgilerini ayrı tut. Arka planda/uygulama kapalıyken izleme ve bildirim garantisi ancak ayrıca doğrulanırsa verilebilir.
- Lig isimleri/eşikleri şartnameden gelir; örnek 8.960 puan ile Oksijen rozeti çelişiyorsa eşikler kazanır. Ağaç eşdeğeri için bilimsel katsayı uydurma; tanımlı katsayı yoksa gösterme veya demo eşdeğeri diye etiketle.

## Kabul testleri ve edge case'ler
- Adım: 0/900/999/1000/1999/2000; +334 ile 6666→7000 yalnız +5; yinelenen sensör olayı, restart/reboot sayacı azalması, gün değişimi, 6000 streak aynı gün tek artış ve kaçırılan gün. Geçersiz adım puan yaratmaz. Eksik GPS ile 0 hareketi ayır.
- Transit: geçerli/geçersiz payload, aynı durak QR ve NFC ortak cooldown; 44:59 reddet, 45:00 kabul; farklı durak ve eşzamanlı/tekrarlanan taramalar. Tek olay tek +3 ve tek CO₂ ödülü. Geçmiş zaman/telefon saati değişimi sınırını belirt.
- Bisiklet: 0.999/1/1.999/2 km; anlık 50 ve üstü, ortalama 35 ve üstü; 25 km/sa çevresinde 0.12 varyans sınırı; negatif/NaN hız, GPS sıçraması ve yetersiz doğruluk, durdur/devam et. Reddedilen aktivitede önceden yazılmış puan kalmamalı; aynı yolculuğa tekrar ceza yok.
- Taksi: 30 km/sa sınırı, adım artışı, son 45 dk transit kaydı, veri yokluğu; aynı yolculuk için tek sayaç artışı ve mesafe×0.192 hesabı. Önlenen ve harcanan CO₂ ayrı tutulur.
- Klan: 4 üye hariç, 5 üye dahil; toplam/hibrit formül, eşitlikte kararlı sıralama, boş liste, tüm zamanlar/haftalık ayrımı. Maskeli ad: boş, 1–2 harf, Türkçe ve emoji; karakter bölme hatası yok.
- Mağaza: yetersiz/tam bakiye, çift dokunma, zaten alınan ürün, kuşanma ve restart kalıcılığı; negatif altın yok.
- Haftalık reset: puan altına bir kez aktarılır; tekrar çağrı çift ödeme yapmaz; şampiyon reset öncesi alınır; haftalık ceza/puan temizlenir, kalıcı envanter korunur. Hafta başlangıcı Pazartesi 00:00 Europe/Istanbul; demo ileri hafta geçişi açıkça modellenir.
- Android: izin reddi/kalıcı ret, konum kapalı, NFC/sensör yok, kamera reddi, uçak modu, yeniden başlatma, arka plan/geri dönüş; okunur hata ve çalışan gezinme. Küçük ekran, büyük yazı, taşan uzun klan adı, klavye ve geri tuşunu kontrol et.
- Testleri iş kurallarına ve kritik akışlara odakla; uygulamayı aynalayan gereksiz testler üretme. Gerçek cihaz smoke testi ile sensör donanım doğrulamasını eşdeğer sayma.
