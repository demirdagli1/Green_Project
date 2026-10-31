# Çalışma sözleşmesi

Önce [DURUM.md](DURUM.md) oku. Güncel kullanıcı mesajı ve bu dosya, arşivdeki eski görev notlarının önündedir. Geçmiş belgeleri topluca tekrar okuma; ilgili kodu ve gereken yönergeyi seç.

## Sorumluluk
- Codex yalnız yönetir, inceler, belge/Git/dağıtım işlerini yapar. Ürün, test, SQL ve uygulama yapılandırma kodunu AGY yazar.
- AGY için son tercih Gemini 3.8 Flash High. Kullanıcı istemedikçe Argon/Claude/Hermes/Deepseek'e geçme. Tokenları koru, kısa konuş, gereksiz tekrar ve mikro yönetim yapma.
- İş paketlerinin sınırını açık koy. Aynı dosyaya iki ajan yazmasın. Ayrı çalışma alanındaki otobüs taslağını onaysız/denetimsiz ana sürüme taşıma.
- Yerel ara commitler at; **push yapma**. AGY commit/reset/checkout yapmaz, Git yönetimi Codex'tedir.
- Kullanıcının dosyalarını ve değişikliklerini koru. Özellikle Düzenlemeler.txt içindeki kullanıcı değişikliklerini sessizce geri alma veya kendi commitine katma.

## Araç ve kaynak sınırı
- SDK, paket, Gradle veya araç indirme/güncelleme yok. Diğer projeler yalnız kurulu araç/önbellek keşfi için salt okunur.
- Flutter: `/home/girdap/Masaüstü/WordMaster/.tools/flutter/bin/flutter`
- JDK 17: `/home/girdap/Masaüstü/WordMaster/.tools/jdk17`
- Pub cache: `/home/girdap/Masaüstü/WordMaster/.tools/pub-cache`
- Android SDK: `/home/girdap/Masaüstü/itiraf/.tools/android-sdk`
- Flutter komutlarında `FLUTTER_NO_VERSION_CHECK=true CI=true`; pub için `--offline`, test için `--no-pub --concurrency=1`.
- Aynı anda yalnız bir ağır test/derleme. Gradle `--offline --no-daemon --max-workers=1`, JVM heap en çok 2 GB, metaspace 512 MB; paralel derleme yok. Kullanılabilir RAM 2 GB altındaysa dur ve bildir. Llama veya başka model sunucusunu kendiliğinden başlatma.
- Telefonun elle testi kullanıcıya aittir. Otomatik ekran gezme, fotoğraf seçme, uygulama kurma veya kullanıcıdan tekrar tekrar yürüyüş isteme yok. Gerekirse kilit/bağlantı için kısa ping at.

## Ürün ve doğrulama
- Kaynak isterler `docs/isterler/`, eski raporlar `docs/arsiv/` içinde. Yeni görev başına MD üretme; güncel durum için DURUM.md kullan.
- Önce işlev ve düzgün yerleşim. Verilen logo/pet görsellerini kullan; gereksiz animasyon, yeni görsel üretimi veya ağ bağımlılığı ekleme.
- Gerçek, demo, taslak ve doğrulanmamış davranışı açık ayır. Test geçmesi fiziksel sensör doğruluğu veya tüm cihazlarda canlı güncelleme kanıtı değildir.
- GPS/kadans/ivme araç türünü kesin ispatlamaz. Yetersiz veri otomatik suçlama/ceza üretmemeli. Arka plan veya kapalı uygulamada takip/bildirim garantisi verme.
- Kritik kuralları, hata ve sınır durumlarını anlamlı testlerle doğrula. Başarılı test/build'i yeni değişiklik veya gerekçe olmadan yineleme.
- Canlı SQL değişikliklerini AGY hazırlar; Codex inceler ve uygular. RLS, özel sütunlar, admin yetkisi, atomik harcama ve aynı olayın iki kez ödüllendirilmemesi korunur.
- Büyük fonksiyon değişikliklerinde hazırlanmış BEGIN/ROLLBACK preflight testini önce çalıştır. Dağıtılmış migration'ı yeniden yazıp uygulama; ayrı artımlı düzeltme kullan.
- Otomatik onay reddini başka araçla aşma. Risk düzeltilir; gerçek bir engel kalırsa reddin eylemini/gerekçesini kullanıcıya açıkla.
- Service-role, yönetici tokenı, cihaz kimliği ve ham GPS kayıtları kaynaklara/raporlara/commitlere konmaz. `.gm-private/` ve `*.private.json` yereldir, Git'e kapalı ve web kökü dışında kalır.
- GM paneli `127.0.0.1:8787`; 8080 kullanıcının başka servisine ayrılmıştır. Panel yetkisi sunucuda doğrulanır, APK veya kamusal anahtar admin sırrı değildir.
