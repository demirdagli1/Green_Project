# Güncel devam noktası — 31 Ekim 2026, 04:12

Bu dosya önceki tüm ara durum raporlarının önüne geçer.

**Revizyon 03 ve Öncelik 1 Bulut Eşitleme Kök Neden Düzeltmeleri Tamamlandı:**
- **Öncelik 1 Kök Neden Analizi ve Düzeltmesi:**
  - Yerel GM kısıtı çözüldü: Doğrudan Supabase'e bağlanan ve `server_admins` doğrulamalı Evrensel GM Paneli (`tools/universal_gm/index.html`) geliştirildi.
  - Outbox Head-of-Line Blocking engeli giderildi: Zehirli paketler (poison-pill) 5 denemeden sonra karantinaya (`quarantined`) alınır; üstel geri çekilme (`retryCount > 1`) ile ağ trafiği dengelenir; arkadaki bekleyen olaylar tıkanmaz.
  - Realtime diğer kullanıcıları yutma hatası giderildi: `hibiscus` ve diğer kullanıcıların puan değişimleri tüm cihazlarda anında güncellenir.
  - Ön plan yaşam döngüsü (`onAppResume`): Uygulama ön plana geldiğinde kesilmiş olabilecek Realtime bağlantısı tazelenir ve outbox kuyruğu tetiklenir.
- **Revizyon 03 Özellikleri (Madde 1-10):**
  - `AutoTransportClassifierService`: Trabzon durakları tohumu ile 2 katmanlı sınıflandırma, GPS sahtekarlık ve düşük doğruluk filtresi; $\le 500m$ otobüs yolculuklarında -3 puan cezası (0 CO2).
  - Klan Utanç Tablosu: Bireyler yerine en çok israf yapan klanlar deterministik listelenir.
  - Bottom Nav: Mükerrer iç QR/NFC sekmesi kaldırıldı.
  - Yeni Launcher İkonu: `Logolar/logo-app.png` ile %18 safe zone marjlı ikonlar üretildi.
  - Klan Lig Logoları: `logo-klan-1..6.png` ve `logo-klan-base.png` entegre edildi (`ClanLeagueBadge`).
  - Utanç Dürtme & Mesajlaşma: 50 karakter sınır, 10 altın maliyet, Europe/Istanbul günlük 1 mesaj kotası ve GM sıfırlama desteği.
  - Kuşanılan Pet: Profil resminin sağında gösterilir (`bit-bee.png`, `auro-fairy.png`).
  - Evrensel GM Web Paneli: `tools/universal_gm/index.html` (REST/RPC doğrudan Supabase).
  - Klan Detay & Hiyerarşi Sayfası: Ana ekrandan klan kartına dokunulduğunda açılan `ClanDetailScreen` (`Lider`, `Kıdemli`, `Üye`).
- **Root Dağıtım Durumu (`ROOT_DAGITIM_BEKLIYOR`):**
  - Sunucu şema ve RPC değişiklikleri `supabase/migrations/06_revizyon_03.sql` içinde hazırlandı ve `AŞAMA_03_DURUM.md` içinde açıklandı. Root tarafından canlı Supabase projesine uygulanması beklenmektedir.
- **Statik Kod Analizi:**
  - `dart analyze` ➔ **0 issue (0 hata, 0 uyarı)**.
- **Otomasyonlu Testler:**
  - `flutter test --no-pub --concurrency=1` ➔ **131 / 131 test BAŞARILI**.
- **Offline APK Teslimatı:**
  - Konum: `releases/YeSilAdim-debug.apk` (173.961.313 bayt)
  - SHA-256: `9a1f7af5a0acfac75279e63281a52d5d8c48d7879d6b923c775610906b382c16`
  - Sürüm Notu: `releases/SURUM_NOTLARI.md`
  - Aşama Raporu: `AŞAMA_03_DURUM.md` (ROOT_ICIN_HAZIR)
- **Kullanıcı Elle Testleri & Kurallar:**
  - Telefona otomatik dokunma/kurulum yapılmamıştır (`adb install -r releases/YeSilAdim-debug.apk` ile elle test edilir).
  - Kesinlikle git komutu (add, commit, push, checkout) kullanılmamıştır.
