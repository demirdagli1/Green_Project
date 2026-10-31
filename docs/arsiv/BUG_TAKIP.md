# Aktif hata ve doğrulama kaydı

## Kapalı — Donanım köprüsü gerçek cihazda kullanılamıyor (öncelikli)
- **Kök Neden Teşhisi:**
  1. Native `MainActivity` (`com.yesiladim.ecoclan/hardware`) ve `SensorController` gerçekte çalışıyor ve tüm yetenekleri (`stepCounter: true, accelerometer: true, gps: true, locationEnabled: true, nfc: true, nfcEnabled: true, sdk: 36`), izinleri (`activity: granted, location: granted, notifications: granted`) ve sensör dinleyicilerini (`SensorManager: registerListener :: 19, Step Counter` ve `LSM6DSOTR Accelerometer`) başlatıyordu (canlı Dart VM `getObject` sorgusu ve `logcat` ile kanıtlandı).
  2. Ancak [home_screen.dart](lib/screens/home/home_screen.dart) içinde `_SensorStatusCard` bileşeni `const _SensorStatusCard()` olarak kullanılmıştı ve kendi içinde `ListenableBuilder(listenable: Hub.sensors, ...)` barındırmıyordu. Uygulama her soğuk açıldığında (son uygulamalardan kapatıp yeniden açma dahil) ilk senkron karede `MainShell._resume()` içindeki `await Hub.sensors.refresh()` / `await Hub.sensors.start()` henüz tamamlanmamışken `_SensorStatusCard` bir kez `caps = {}`, `sensorsRunning = false` ile çiziliyor; birkaç milisaniye sonra native yanıt gelip `Hub.sensors.notifyListeners()` çağrıldığında ise `HomeScreen` yeniden çalışmasına rağmen `const _SensorStatusCard()` derleme zamanı sabiti (`identical(oldWidget, newWidget) == true`) olduğu için Flutter `Element.updateChild` optimizasyonu alt bileşenin `build()` metodunu atlıyordu.
  3. İzinler zaten `granted` olduğu için `"İzinleri iste"` düğmesine basıldığında Android'in yeniden sistem izin penceresi açmaması normaldir; ancak `const _SensorStatusCard` yeniden çizilmediği için düğme tepkisiz görünüyordu.
- **Çözüm ve Kanıt:**
  - [home_screen.dart](lib/screens/home/home_screen.dart) içinde `_SensorStatusCard` üzerinden `const` kaldırıldı ve kendi `build()` metodu `ListenableBuilder(listenable: Hub.sensors, ...)` ile sarmalandı.
  - Kart üzerinde gerçek donanım yetenekleri (`Donanım: Adımsayar var • GPS açık • NFC açık (API 36)`) ve izin durumları (`İzinler: Aktivite verildi • Konum verildi • Bildirim verildi`) açıkça gösterildi; izinler verilmişken düğme `"Durumu yenile (İzinler verildi)"` olarak güncellendi ve basıldığında bilgi `SnackBar`'ı eklendi.
  - [hardware_bridge.dart](lib/services/hardware_bridge.dart) ve [sensor_controller.dart](lib/services/sensor_controller.dart) içinde olası kanal/platform hatalarını sessizce gizlemek yerine `lastError` / `bridgeError` alanı ile yüzeye çıkaran teşhis eklendi; `start()` içinde `caps.isEmpty` ise önce `refresh()` çağrılması sağlandı.
  - [MainActivity.kt](android/app/src/main/kotlin/com/yesiladim/ecoclan/green_project/MainActivity.kt) içinde sistem bildirim kanalı `IMPORTANCE_HIGH` / `PRIORITY_HIGH` yapıldı; `dumpsys notification` ile gerçek `StatusBarNotification` nesneleri doğrulandı.
  - [ui_flow_test.dart](test/ui_flow_test.dart) içine asenkron donanım köprüsü yanıtı sonrası `HomeScreen` sensör kartının güncellendiğini doğrulayan regresyon testi eklendi (`58/58` test geçti).
  - Güncel APK cihaza kuruldu ve [evidence/screen_04_home.png](evidence/screen_04_home.png) / [evidence/manager_current.png](evidence/manager_current.png) görüntülerinde gerçek cihazda `"📡 Sensörler açık (yalnız uygulama ön plandayken)"`, `"Donanım: Adımsayar var • GPS açık • NFC açık (API 36)"` ve `"İzinler: Aktivite verildi • Konum verildi • Bildirim verildi"` metinlerinin göründüğü kanıtlandı.

## Kapalı — DURUM.md/README doğruluk sorunları
- Hibrit formül (`0.6 × ToplamPuan + 0.4 × 50 × ÜyeOrtalaması`), bireysel lig adları (`Karbonmonoksit`, `Karbondioksit`, `Azot`, `Oksijen`, `Ozon`, `Sönmez Biyosfer`), `0.12` varyans eşiği, maskeleme açıklaması, `Android 16 / API 36` (`adb getprop` kanıtlı) bilgisi ve relative dosya bağlantıları [README.md](README.md) ve [DURUM.md](DURUM.md) üzerinde düzeltildi; yanlış etiketli `screen_05_qr_nfc.png` referansı kaldırıldı.

## Kapalı — Küçük ekran taşması
- MainShell IndexedStack altında offstage leaderboard sabit Column kaynaklı dikey taşma düzeltildi.
- [evidence/test_all.log](evidence/test_all.log): 58/58 geçti. [evidence/analyze.log](evidence/analyze.log): No issues found. Güncel offline build: 18s başarı.

## Kullanıcı testi düzeni
- Kullanıcı cihazı elle test edip hataları iletecek. Tekrarlanan otomatik ekran tıklamalarıyla kullanıcıya çakışma yaratma; cihazda değişiklik/install/restart gerekiyorsa yöneticinin haberi olsun.
- Yeni kullanıcı raporlarını bu dosyaya tekil kayıt olarak ekle; tekrar eden uzun istemler üretme.
