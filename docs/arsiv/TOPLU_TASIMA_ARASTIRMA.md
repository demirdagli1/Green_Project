# QR / NFC toplu taşıma entegrasyonu için veri listesi

## Kullanıcının toplayacağı bilgiler
1. İşletme: Trabzon belediye otobüsü mü, KTÜ ringi mi, başka işletme mi? Teknik iletişim/API dokümanı veya açık veri adresi.
2. Kimlikler: hat kodu, araç/validator kodu, durak kodu; bunların birbirine eşleme listesi. Gidiş/dönüş güzergâhı ve ortalama/gerçek mesafe.
3. QR: örnek anonim tarama sonucu düz metin/URI/JSON; kod sabit mi değişiyor mu, araçta mı bilette mi, süre/işlem kimliği/imza var mı?
4. NFC: kendi yapıştıracağımız NDEF etiket mi, mevcut ulaşım kartı mı, araç okuyucusu mu? Teknoloji ve izinli örnek NDEF içeriği/API dokümanı. Tam kart/ödeme bilgisi gerekmez.
5. Biniş kanıtı: işletme API'si binişin başarılı olduğunu belirten işlem kimliği/zamanı/araç-hat kimliği sağlayabiliyor mu? Test ortamı ve örnek anonim yanıt. Erişim anahtarının nerede tutulacağı/sunucu doğrulaması tasarımı sonra bu sözleşmeye göre belirlenir.
6. Konum/zaman verisi varsa: GTFS Schedule URL'si ve lisansı; GTFS Realtime/API varsa erişim, yenileme sıklığı, araç/hat kimliklerinin statik veriyle eşleşmesi.
7. CO₂: hesapta kullanılacak karşılaştırma katsayısı ve kaynak; inilen durak bilinmiyorsa ortalama mesafe kullanımı açık tahmin olarak işaretlenir.

## Üç ayrı kapsam
| Seçenek | Gereken | Ne doğrular? | Sınır |
|---|---|---|---|
| Hackathon demosu | YESILADIM://TRANSIT/<kod> içeren kendi QR/NDEF etiketi + yerel durak listesi | Kodu/etiketi gördüğünü ve uygulama kurallarını | Sabit kod kopyalanabilir; gerçek ücretli biniş kanıtı değildir |
| Kendi araç/ring etiketimiz | İşletme izniyle araç etiketi, araç/hat kayıtları; tercihen zamanlı imzalı kod ve sunucu kontrolü | Tanımlı araç/etiketle ilişki ve geçerlilik | Statik NFC UID veya fotoğrafı çekilen QR tek başına güçlü biniş kanıtı olmaz |
| Gerçek biniş entegrasyonu | İşletmenin yetkili validator/bilet doğrulama API'si, test sözleşmesi ve işlem kimliği | API'nin sağladığı başarılı biniş işlemini | Akış/izin/erişim işletmeye bağlı; genel NFC okuyarak bütün ulaşım kartlarını çözme varsayımı yapılamaz |

GTFS Schedule hat/durak/sefer/zaman/güzergâh verisidir; GTFS Realtime araç konumu/sefer güncellemesi/uyarı gibi veriler sağlar. Bunlar tek başına belirli kullanıcının biniş/ödeme kaydı değildir. Kart UID'si de biniş işlem kaydı değildir; Android bazı etiketlerin rastgele kimlik üretebildiğini veya hiç kimlik taşımadığını belirtir.

## Uygulama tarafında korunacak sözleşme
- QR ve NFC aynı canonical durak/araç kimliğine normalize edilir; ortak45dk cooldown, tek işlem kimliği ve tek ödül.
- Boş/bozuk/bilinmeyen payload, yanlış hat, süresi geçmiş imza, tekrar oynatma, çevrimdışı durum ve saat geriye alma açık sonuç verir.
- NDEF URI/Text kayıtlarının payload yapısı doğru çözümlenir; raw byte dizisini doğrudan UTF8 sanmak URI öneki/dil kodunu yanlış yorumlatabilir.
- Biniş ve iniş noktası varsa güzergâh mesafesi; yoksa açıkça etiketli tahmin. Demo katsayısı bilimsel doğrulanmış sonuç gibi sunulmaz.
- İşletmeden örnek gelmeden API adresi/anahtarı/şema uydurulmaz. Uzak sunucu/veritabanına kendiliğinden değişiklik yapılmaz.

## Birincil kaynaklar — 30 Ekim 2026 incelemesi
- [Android NFC temelleri: NDEF ve tag dispatch](https://developer.android.com/develop/connectivity/nfc/nfc)
- [Android Tag.getId: UID kısıtları](https://developer.android.com/reference/android/nfc/Tag#getId())
- [GTFS genel bakış](https://gtfs.org/documentation/overview/)
- [GTFS Schedule alanları](https://gtfs.org/documentation/schedule/reference/)
- [GTFS Realtime genel bakış](https://developers.google.com/transit/gtfs-realtime)
