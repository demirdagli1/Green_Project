# Yeşil Adım — Sürüm Notları (Revizyon 03 & Bulut Eşitleme Düzeltmeleri)

- **Tarih:** 31 Ekim 2026
- **Derleme Tipi:** Debug (Tamamen Çevrimdışı, 1 worker, 2GB JVM Heap, JDK 17)
- **Dosya Adı:** `YeSilAdim-debug.apk`
- **Dosya Boyutu:** ~166 MB (173.965.301 bayt)
- **SHA-256 Özeti:** `1f09907ec13f3f31ba3ddc58721a7eb331546cef309e658c908290142827d19b`
- **Hedef Platform:** Android (arm64-v8a, armeabi-v7a, x86_64)

---

## 🌟 Öncelik 1: Gerçek Cihazlar Arası Eşitleme ve Outbox İyileştirmeleri
1. **Head-of-Line Blocking Giderildi:** Başarısız veya şema uyuşmazlığı yaşayan outbox olayları kuyruğu tıkamamakta; 5 başarısız denemeden sonra zehirli paket olarak karantinaya (`status = quarantined`) alınmakta ve arkadaki bekleyen olaylar kesintisiz sunucuya iletilmektedir.
2. **Realtime Çoklu Cihaz Güncellemesi:** Realtime dinleyicisindeki filtreleme düzeltildi; diğer kullanıcıların (örneğin 3. cihazdaki `hibiscus`) puan ve adım değişimleri yerel tabloya anında yansıtılmaktadır.
3. **Ön Plan Yaşam Döngüsü (App Resume):** Uygulama arka plandan ön plana geldiğinde kopmuş olabilecek Supabase Realtime WebSocket kanalı taranmakta ve bekleyen outbox kuyruğu otomatik tetiklenmektedir.
4. **Evrensel GM Paneli (`tools/universal_gm/index.html`):** Yerel loopback `127.0.0.1:8088` kısıtlaması yerine doğrudan Supabase veritabanına bağlanan ve `server_admins` tablosuyla yetkilendirilen harici web yönetim konsolu hazırlandı.

---

## 🌟 Revizyon 03 Kapsamında Eklenen Özellikler

### 1. Otomatik Toplu Taşıma Sınıflandırıcısı ve Kısa Otobüs Cezası (Madde 1 & 2)
- İki katmanlı hibrit karar ağacı: GPS hızı, ivmeölçer örüntüsü ve Trabzon durakları tohum veritabanı eşleştirmesi.
- Düşük GPS doğruluğu koruması ($accuracy > 35m$) ve sahte konum / imkansız sıçrama filtresi ($speed > 160 km/s$).
- $\le 500m$ (0.5 km) kısa otobüs yolculuklarında **-3 haftalık puan cezası** ve **0 CO2 kazancı** kuralı hem istemciye hem de `rpc_record_bus_trip` sunucu fonksiyonuna işlendi.

### 2. Klan Utanç Tablosu (Madde 3)
- Liderlik tablosundaki Utanç sekmesi bireysel kullanıcılar yerine haftalık en çok CO2 israfı yapan klanları sıralar (`v_worst_clans`).

### 3. Bottom Navigasyon Sekme Sadeleştirmesi (Madde 4)
- Transit / Bisiklet modalındaki mükerrer iç `Otobüs QR / NFC` TabBar'ı kaldırılarak tekil ve temiz bir görünüme kavuşturuldu.

### 4. Yeni Android Uygulama İkonu (Madde 5)
- `Logolar/logo-app.png` kaynak görselinden Android için `mdpi`, `hdpi`, `xhdpi`, `xxhdpi`, `xxxhdpi` launcher ikonları üretildi. Yuvarlak simge maskelerinde logonun kenarlarının kesilmemesi için %18 güvenli alan marjı uygulandı.

### 5. Klan Lig Logoları (Madde 6)
- `Logolar/logo-klan/logo-klan-1..6.png` ve `logo-klan-base.png` dosyaları projeye dahil edildi. Ortak `ClanLeagueBadge` bileşeni ile klanların lig seviyesine göre logoları ana ekranda ve klan detayında gösterilmektedir.

### 6. Utanç Tablosu Dürtme & Mesajlaşma (Madde 7)
- Utanç listesindeki kullanıcı veya klanlara 50 karakterle sınırlı dürtme mesajı gönderme özelliği eklendi.
- İşlem başına 10 altın düşülür; gönderici başına Europe/Istanbul saat dilimine göre günde en fazla 1 mesaj gönderilebilir. Günlük kota GM panelinden sıfırlanabilir.

### 7. Kuşanılan Pet Gösterimi (Madde 8)
- Profil sayfasında kullanıcının kuşandığı pet (`bit-bee.png`, `auro-fairy.png`) profil resminin hemen sağında görüntülenir.

### 8. Klan Detay ve Hiyerarşi Sayfası (Madde 10)
- Ana ekrandan klan kartına dokunulduğunda açılan `ClanDetailScreen` sayfası eklendi.
- Klan üyeleri haftalık puana göre sıralanır ve `Lider` (1. sıra), `Kıdemli` (2. ve 3. sıra), `Üye` (diğerleri) rolleri deterministik olarak atanır.

---

## 🧪 Doğrulama ve Test Sonuçları
- **Statik Kod Analizi:** `dart analyze` ➔ **0 issue (0 hata, 0 uyarı)**.
- **Otomasyonlu Testler:** `flutter test --no-pub --concurrency=1` ➔ **131 / 131 test BAŞARILI**.
- **Çevrimdışı Android Derlemesi:** Tek worker / 2 GB JVM Heap / JDK 17 ile **18 saniyede başarılı** (`releases/YeSilAdim-debug.apk`).

---

## ⚠️ Kullanıcı Elle Test ve Kapsam Notları
1. **Elle Cihaz Testleri Kullanıcıda:** Talimat gereğince telefona otomatik dokunma/kurulum yapılmamış, telefon mevcut ekranında bırakılmıştır; elle testler kullanıcıya aittir (`adb install -r releases/YeSilAdim-debug.apk`).
2. **Kök Dağıtımı (`ROOT_DAGITIM_BEKLIYOR`):** Sunucu tarafındaki şema, görünüm ve RPC değişiklikleri `supabase/migrations/06_revizyon_03.sql` içinde toplanmıştır. Root kullanıcısı tarafından canlı Supabase projesine uygulanması beklenmektedir.
3. **Sensör Sezgisi Sınırları:** GPS sapmaları ve düşük sinyal ortamları için koruma katmanları mevcuttur; gerçek donanım testlerinde tünel ve kapalı alan durumları göz önünde bulundurulmalıdır.
