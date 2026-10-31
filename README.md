# Yeşil Adım

Yürüyüş ve bisiklet kullanımını puan, lig, klan ve kozmetik ödülleriyle teşvik eden Flutter tabanlı Android uygulaması.

## Projenin amacı

Günlük hareketi görünür hale getirmek ve çevreci ulaşım alışkanlıklarını oyunlaştırmak. Bireysel sıralamalar kişisel ilerlemeyi, klanlar ise birlikte hareket etmeyi destekler. CO₂ değerleri mesafeye dayalı tahminlerdir; doğrudan emisyon ölçümü değildir.

## Özellikler

- Adım takibi ve her tamamlanan 1.000 adım için 5 puan.
- Yürüyüş ve bisiklet için hareket algılama ve sürüş kaydı.
- Supabase üzerinden ortak bireysel ve klan sıralamaları.
- Araç yolculuklarının tahmini CO₂ israfına göre utanç tablosu.
- Gerçek kullanıcılara 10 altın karşılığında, en fazla 50 karakterlik ve günlük bir adet mesaj.
- Profil fotoğrafı, biyografi, avatar, çerçeve ve kuşanılabilir petler.
- Yetkili PC yönetim panelinden kullanıcı seçerek test işlemleri ve bildirim gönderimi.

Alt gezinme menüsü **Ana Sayfa, Sıralamalar ve Profil** sekmelerinden oluşur.

## Teknolojiler

| Katman | Kullanılan teknoloji |
| --- | --- |
| Mobil arayüz ve uygulama kuralları | Flutter / Dart |
| Android sensör ve bildirim erişimi | Kotlin |
| Kimlik doğrulama ve ortak veri | Supabase Auth / PostgreSQL |
| Veri erişim kuralları | RLS ve sunucu fonksiyonları |
| Canlı güncelleme | Supabase Realtime ve periyodik yenileme |
| PC yönetim paneli | HTML / JavaScript |

## Dosya yapısı

```text
lib/
  screens/       Ekranlar ve gezinme
  services/      Uygulama durumu, sensörler ve Supabase bağlantısı
  models/        Veri modelleri
  widgets/       Ortak arayüz bileşenleri
  core/          Sabitler ve yardımcı işlevler
android/         Android projesi ve Kotlin köprüsü
test/            Otomatik testler
supabase/        Şema değişiklikleri ve doğrulama SQL dosyaları
tools/universal_gm/  PC yönetim paneli
Logolar/         Logo ve kozmetik görselleri
releases/        Sürüm notları ve APK sağlama toplamı
```

## Geliştirme ve çalıştırma

Flutter, Android SDK ve uygun JDK kurulumu gerekir. Bağımlılıklar `pubspec.yaml` ve `pubspec.lock` dosyalarında tanımlıdır.

```bash
flutter pub get
flutter run
```

Önbellekteki bağımlılıklarla çalışmak için `flutter pub get --offline` kullanılabilir. Supabase bağlantısı için projenin yapılandırma kaynaklarını inceleyin. Yeni bir sunucuya geçerken kimlik doğrulama, şema, erişim kuralları ve Realtime yapılandırması birlikte hazırlanmalıdır; SQL dosyalarını mevcut veritabanına körlemesine uygulamayın.

## Test ve derleme

```bash
flutter analyze
flutter test --no-pub --concurrency=1
flutter build apk --debug --no-pub
```

Otomatik testler uygulama kurallarını ve veri akışını kontrol eder. Gerçek sensör doğruluğu, telefonların pil yönetimi, bildirim teslimi ve farklı cihazlarda canlı görünüm ayrıca fiziksel cihazlarla doğrulanmalıdır.

APK dosyaları ve yerel yönetici oturumları Git deposuna dahil edilmez.

## PC yönetim paneli

Proje kökünden:

```bash
python3 -m http.server 8787 --bind 127.0.0.1 --directory tools/universal_gm
```

Tarayıcıda `http://127.0.0.1:8787` adresini açın. Panel işlemleri sunucuda yönetici yetkisi gerektirir. Yönetici oturum dosyaları ve gizli anahtarlar paylaşılmaz; web sunucusunun köküne konmaz.

## Geliştirme kapsamı

Otomatik otobüs doğrulaması ve 500 metreye kadar kısa otobüs yolculuğu cezası ana sürümde etkin değildir. Uygulama kapalıyken bildirim teslimini sağlayan FCM altyapısı bulunmaz. Sensörlerden çıkarılan ulaşım türü kesin bir kanıt olarak değerlendirilmemelidir.
