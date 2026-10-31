# Yeşil Adım — Sunum Çalışma Notu

Bu not, jüride projeyi teknik terimlere boğulmadan, günlük konuşma diliyle ve en basit haliyle anlatabilmen için hazırlandı. Ezber yapmana gerek yok; mantığı bilmen yeterli.

---

## 1. Hocaya 1–2 Dakikalık Açılış Konuşması

Hocanın karşısına geçtiğinde doğrudan şunu söyleyebilirsin:

"Hocam merhaba. Projemizin adı Yeşil Adım. Amacımız insanların kısa mesafelerde arabaya binmek yerine yürümesini, bisiklete binmesini ve otobüsü tercih etmesini sağlamak.

Bunu küçük bir oyuna çevirdik. Ayşe okula yürürken telefon adımlarını sayıyor. Her 1.000 adımda 5 puan kazanıyor. İnternet yoksa uygulama kayıtları telefonda biriktirip bağlantı gelince göndermeyi deniyor.

Ayşe bu puanlarla arkadaşlarıyla yarışıyor. İsterse bir gruba, yani klana katılıyor; kazandığı puan klanına da katkı sağlıyor. Hafta sonunda puanları altına dönüşüyor. Altınla profilinde duracak küçük maskotlar alıyor.

Bir de ters yarış var: Gereksiz araba kullanımını azaltmak için Utanç Tablosu koyduk. Telefon hareketten araç kullanımını tahmin etmeye çalışıyor. Bu kesin bir ölçüm değil; otobüsle arabayı ayırma kısmını geliştirmeye devam ediyoruz.

Ekranları Flutter ile yaptık. Ortak puan listesini Supabase'de tutuyoruz. Temel ekranlar ve puan kuralları var; telefonların aynı puanı görmesi ve otomatik ulaşım tahmini üzerinde çalışıyoruz. Şimdi telefonda göstereyim."

---

## 2. Telefonda Sırayla Gösterilecek 5 Şey

Kabloya gerek yok, telefonu eline alıp şu sırayla dokun:

1. **Ana Ekran:** Ortadaki adım çarkını göster. "Burada günlük adımlar ve 6.000 adımda yanan seri ateşi var."
2. **Sıralama Ekranı:** Ligleri göster. "Puan arttıkça Karbonmonoksit liginden Biyosfer ligine çıkılıyor." Yan sekmeden Utanç Tablosu'nu aç: "Arabaya binenler de burada ifşa ediliyor."
3. **Toplu Taşıma / Bisiklet Ekranı:** Trabzon ve KTÜ duraklarını göster. "Otobüse binince durak seçip puan alabiliyor (otomatik tahmin kısmı geliştirme aşamasında)."
4. **Profil ve Mağaza:** Altın bakiyesini ve petleri (Bit-Bee maskotu) göster. "Haftalık biriken puanlar altına dönüşüyor ve buradan pet alınıyor."
5. **GM Test Butonu:** Test ekranını aç. "Hocam şu an odada 10.000 adım atamayacağımız için bu test butonunu koyduk; basınca sanki yürümüşüz gibi sistemi deniyoruz."

---

## 3. Sistem Nasıl Çalışıyor? (Basit Benzetmelerle)

* **Adım sayma:** Telefonun kendi adım sensörünü kullanıyoruz. Sallayarak puan kazanmayı azaltmak için hız ve hareket verilerini de kontrol etmeye çalışıyoruz; her hileyi kesin yakaladığımızı söylemiyoruz.
* **İnternet yoksa:** Uygulamanın içinde küçük bir giden kutusu (not defteri) var. İnternet kesilse bile adımlar oraya not ediliyor. İnternet gelince sırayla ortak listeye postalanıyor.
* **Aynı adımı iki kez saymamak:** Telefon, gönderdiği her yürüyüş kaydına bir numara verir. İnternet kopunca aynı kayıt tekrar giderse sunucu numarasından tanır: "Bunu zaten saydım." Böylece aynı yürüyüşe iki kez puan verilmez.
* **Güvenlik:** Altın harcama ve yönetici işlemleri internetteki sistemde de kontrol ediliyor. Normal kullanıcıya yönetici yetkisi verilmiyor. Bu, telefon verisinin asla taklit edilemeyeceği anlamına gelmiyor.
* **Gerçek durum:** Tek bir telefonda puanlar, mağaza, hile kontrolleri çalışıyor. Ancak 3 farklı telefonda puanların anlık olarak birbirine eşitlenmesi ve arka planda otomatik otobüs tahmini halen **geliştirme aşamasındadır**.

---

## 4. Hoca Sorarsa 2 Cümlelik Cevaplar

* **Neden Flutter seçtin?**  
  Ekranları tek yerde hazırlamak kolay olduğu için seçtik. Bu projeyi Android'de geliştiriyoruz; iPhone sürümünü test etmedik.

* **Telefonu arabada sallarsam bisiklet sanır mı?**  
  Karıştırabilir. Bu yüzden yalnız hıza değil adımlara ve sarsıntıya da bakmaya çalışıyoruz; gerçek yolculuklarla daha çok denememiz gerekiyor.

* **İnternetim biterse ne olur?**  
  Kayıtlar önce telefonda birikir, bağlantı gelince gönderilmeye çalışılır. Bekleyen kayıtların sorunsuz aktarılmasını ayrıca test ediyoruz; uygulamayı silersen yerel kayıtlar kaybolabilir.

* **QR kodla otobüse bindiği kesin anlaşılır mı?**  
  Hayır, biri kodun fotoğrafını evden de kullanabilir. Gerçek binişi doğrulamak için ulaşım şirketinden doğrulanabilir veri almak gerekir; o bağlantı henüz yok.

* **Sürekli GPS açık kalırsa pil bitmez mi?**  
  GPS pil tüketir. Bu sürüm için uzun yolculukta pil ölçümü henüz yapmadık; ekran kapalıyken kesintisiz takip garantisi vermiyoruz.

* **Bu projede senin payın ne, yapay zekanın payı ne?**  
  Fikri, puan kurallarını, ekran yerleşimlerini ve telefondaki gerçek saha testlerini ben yönettim. Kodların yazımı ve hataların ayıklanmasında yapay zekayı (AGY) akıllı bir kodlama asistanı olarak kullandım.

---

## 5. Bilmediğin Bir Şey Sorulursa Ne Diyeceksin?

Asla ezbere uydurma yapma. Şu iki cümleyi kurman hocanın gözünde seni dürüst ve gerçekçi bir mühendis yapar:

> "Hocam o kısmı henüz tamamlamadık, şu an geliştirme aşamasındayız. Şu anki çalışan sürümde odaklandığımız yerel kuralları doğrulamaktı; söylediğiniz senaryoyu bir sonraki sürüme not aldık."

---

## 6. Hangi Dosya Ne İşe Yarar? (Küçük Bakmalık Tablo)

Hoca "Koda bakalım, nerede bu?" derse bu tabloya bakıp ilgili dosyayı açabilirsin:

| Dosya Yolu | Ne İşe Yarar? (Çok Basit) |
| :--- | :--- |
| [lib/main.dart](lib/main.dart) | Uygulamanın ana kapısı, her şeyi buradan başlatır. |
| [lib/screens/home/home_screen.dart](lib/screens/home/home_screen.dart) | Ana ekrandaki adım çarkını ve sayaçları çizer. |
| [lib/screens/leaderboard/leaderboard_screen.dart](lib/screens/leaderboard/leaderboard_screen.dart) | Lig sıralamasını ve Utanç Tablosu'nu gösterir. |
| [lib/screens/shop_profile/shop_profile_screen.dart](lib/screens/shop_profile/shop_profile_screen.dart) | Profil bilgilerini ve pet alma mağazasını gösterir. |
| [lib/services/activity_validation_service.dart](lib/services/activity_validation_service.dart) | Puanları hesaplar, telefonu sallama hilesini yakalar. |
| [lib/services/app_store.dart](lib/services/app_store.dart) | Uygulamanın hafızasıdır; adımı, altını aklında tutar. |
| [lib/services/supabase_outbox.dart](lib/services/supabase_outbox.dart) | İnternet yokken adımları biriktiren giden kutusudur. |
| [lib/services/supabase_service.dart](lib/services/supabase_service.dart) | Puanları internetteki ortak listeye gönderen servistir. |
| [android/.../MainActivity.kt](android/app/src/main/kotlin/com/yesiladim/ecoclan/green_project/MainActivity.kt) | Telefonun adım sensörüne ve GPS'ine bağlanan köprüdür. |

---

## 7. Git Geçmişi ve Commitler

Hoca projenin gelişim sürecini görmek isterse terminalde sadece şu salt okunur komutları çalıştır:

```bash
git log --oneline -n 10
git show --stat cda28f9
git diff --stat ba641a3..be495d3
```

### Önemli Commitler ve Gerçek Anlamları:

* `ba641a3`: İlk çalışan sürüm. 103 otomatik test çalıştırıldı ve ilk test APK paketi derlendi.
* `be495d3`: İnternetteki ortak liste (Supabase) altyapısı bağlandı. İstemci raporunda 114 test kaydedildi; ancak bu testler canlı iki cihaz senkronizasyonunun kanıtı değildir.
* `af1d72d`: Revizyon 03 kapsamını, klan/pet resimlerini ve şartnameleri ekleyen belge kaydıdır; işlerin bittiği anlamına gelmez.
* `cda28f9`: Revizyon 03 arayüzünü, pet/klan görsellerini ve senkronizasyon düzeltmelerini içeren çalışma kaydıdır (WIP). Kayıt kaybolmasın diye alınmıştır, henüz canlı sunucu onayı yoktur.
* `f5d950b` ve `fa90027`: Sunum çalışma rehberini ve sunucu durum açıklamalarını ekleyen belge kayıtlarıdır.

*(Not: Test raporlarında geçen 103, 114 ve son 132 test sayıları yazılımın kod içi akışlarını doğrulamıştır; canlı ortamda birden fazla cihazın eşitlenmesi henüz tamamlanmamış olup geliştirilmektedir).*
