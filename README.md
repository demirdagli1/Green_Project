# Yeşil Adım (EcoClan)

Yeşil Adım, sürdürülebilir kentsel hareketliliği (yürüme, bisiklet, toplu taşıma) teşvik eden, klan temelli gamification ve karbon ayak izi takip mobil uygulamasıdır.

## 🚀 Proje Durumu ve Özet

- **Statik Kod Analizi:** `dart analyze` ile 0 hata, 0 uyarı
- **Test Kapsamı:** 58 / 58 test başarılı (`rules_test`, `store_test`, `ui_flow_test`)
- **Derleme Modu:** Tamamen çevrimdışı (offline Gradle 9.3.1, JDK 17, AGP)
- **Fiziksel Cihaz Doğrulaması:** Samsung SM-A346E (Android 16 / API 36) üzerinde kurulum, donanım köprüsü yetenek/izin sorgusu ve sistem bildirimi doğrulandı (fiziksel yürüyüş ve fiziksel NFC etiketi okutma kullanıcı testine tabidir).
- **Ekran Uyum Testi:** 320x568 küçük ekran + %160 metin boyutu altında taşmasız dinamik yerleşim.

---

## 📱 Temel Modüller ve Özellikler

1. **Onboarding & Klan Seçimi:**
   - Kullanıcı adı ve üniversite / mahalle klanı seçimi ile hızlı başlangıç.
   - Yerel kalıcı profil (`SharedPreferences`).

2. **Ana Sayfa & Aktivite Takibi:**
   - Adım sayacı ve 1000 adımda bir +5 puan mekanizması.
   - Kadans (>185 adım/dk) ve GPS sallama hilesi koruması.
   - Bireysel lig kademeleri (`Karbonmonoksit`, `Karbondioksit`, `Azot`, `Oksijen`, `Ozon`, `Sönmez Biyosfer`) ve klan lig kademeleri.
   - Önlenen CO₂ salımı (kg) ve demo ağaç eşdeğeri göstergesi.

3. **Toplu Taşıma (QR & NFC):**
   - Tek biniş için +3 puan ve sabit CO₂ tasarrufu.
   - 45 dakikalık durak bazlı ortak cooldown kuralı (aynı durakta mükerrer biniş engeli).
   - Manuel payload girişi ve simülasyon desteği.

4. **Bisiklet ve Araç/Taksi Denetimi:**
   - Bisiklet sürüşlerinde mesafe bazlı puanlama ve >25 km/sa hızda ivmeölçer varyans eşiği (`0.12`).
   - Araç/taksi kullanımında (>30 km/sa) son 45 dk transit binişi yoksa harcanan CO₂ hesabı ve Utanç Tablosu kaydı.

5. **Liderlik ve Utanç Tablosu:**
   - **Gurur Tablosu:** Bireysel ve klan bazlı haftalık/tüm zamanlar sıralamaları, hibrit normalize klan puanı hesabı (`0.6 × ToplamPuan + 0.4 × 50 × ÜyeOrtalaması`).
   - **Utanç Tablosu:** Harcanan CO₂ miktarına göre sıralama ve isim maskeleme (`Pel***`; yalnızca görsel gizleme sağlar, hukuki uyumluluk garantisi değildir).

6. **Kozmetik Mağazası & Envanter:**
   - Haftalık puanların altına dönüştürülmesiyle avatar, çerçeve ve evcil hayvan satın alma ve kuşanma.

7. **Jüri & Admin Paneli:**
   - Hafta atlatma simülasyonu, puanların altına dönüştürülmesi, sensör testleri ve durum denetimi.

---

## 🛠️ Gerçek / Demo / Eksik Özellik Ayrımı

- **Gerçek:** Yerel kalıcılık, tüm puanlama ve hile algoritmaları, lig hesapları, cooldown takibi, mağaza envanteri, duyarlı arayüz yerleşimi, Android donanım köprüsü (yetenek/izin sorgusu, ön plan sensör dinleme, sistem bildirimi).
- **Demo:** Canlı backend olmadığı için rakip kullanıcılar ve rakip klan verileri tohum simülasyonudur.
- **Eksik / Sınırlar:** Canlı Supabase bağlantısı ve cihazlar arası Realtime senkronizasyonu doğrulanmadı (istemcide `service_role` kullanılmaz; E-posta/SMS/OTP zaten kapsam dışıdır). Fiziksel kamera QR paketi yerel önbellekte bulunmadığından manuel kod girişi kullanılır.

Detaylı doğrulama kayıtları ve ekran görüntüleri için [DURUM.md](DURUM.md) ve `evidence/` dizinine bakabilirsiniz.

---

## 📦 Derleme ve Çalıştırma

```bash
# Testleri çalıştırma:
flutter test --concurrency=1

# Offline APK derleme:
cd android
./gradlew assembleDebug --offline --no-daemon --max-workers=1

# Cihaza yükleme:
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```
