# Root incelemesi — 06 migration henüz DAĞITILMADI

Kullanıcı AGY devam, az root token/kısa iletişim istedi. Görevi tamamla, yalnız somut blocker raporla.

06_revizyon_03.sql ilk taslağında dağıtım engelleri var. İstemci işini bitirmeden önce şunları gider, bütününü anlamlı rollback testleriyle doğrula. Root ürün/SQL kodu yazmayacak.

- Mesaj günlük kota kontrolü sender satır kilidinden ÖNCE: farklı idempotency key ile yarışta iki gönderim geçer. Gönderen kilidi altında kota kontrolü/unique kota kaydı gerekir. Global idempotency key başka gönderenin kaydını sonuç diye döndürmesin; auth kimliğine scope edilmeli. GM de idempotency kontrolünü kilit olmadan yapıyor, yarış double mutation yaratır. Reset kotası mesaj geçmişini/idempotency kaydını SİLMEMELİ: reset edilmiş kota durumu ayrı tutulsun; eski retry yeniden altın kesmesin.
- Bildirim insert kolonları ve activity_type/verification_status CHECK değerleri canlı 01_schema ile birebir eşleşmeli. Clan_role INVOKER view için gereken sütun grantini kontrol et. Yeni definer RPC'lerden varsayılan PUBLIC/anon EXECUTE yetkisini açık kaldır, authenticated kontrollü bırak.
- Bus RPC p_bus_score kullanılmıyor; 0/negatif/null/NaN mesafe bile +3 ödüllendiriyor. Sunucuda doğrulanmış kanıt/mesafe/yeterli güven/eşik/cooldown/journey id şartları olmalı. p_is_short_penalty istemci bayrağı tek başına karar vermesin. Otomatik/QR/NFC aynı yolculuk tek settlement: mevcut transit ödülüyle ortak idempotency/cooldown. Kısa cezada gerçek düşen puan ve klan toplamı tutarlı olsun; 0 bakiyede -3 düşmüş gibi bildirim yanlış. Ödül/ceza günlük tekrar spam olmasın. Sonuçlar puan değişikliği öncesinde doğru sınıflansın.
- GM sayısal girdiler sınırlı/negatif/null/overflow güvenli; add/set adım/puan/seri klan/lig/ödül kuralları tutarlı olmalı. Admin audit FK auth kullanıcı kaydıyla uyumlu olsun. PC panel giriş ve yetkilendirme somut kurulabilir olsun.
- Root'un REVIZYON_03.md içine yazdığı advisor ERROR/mutable search_path bulguları henüz taslakta düzeltilmemiş; düzelt. REPLICA IDENTITY FULL özel gold/device sütunlarını Realtime yoluyla herkese açmamalı; gerçek restricted-role payload/iki oturum kontrolü gerekir. Public yalnız güvenli olay/leaderboard projection kullanmak gerekebilir.
- Root dağıtım için HAZIR olduğunda AŞAMA_03_DURUM.md dosyasına net yaz. Taslak yazılmış diye bitmiş kabul etme. Eski mock test başarısı gerçek cihazlar arası uçtan uca kanıt değildir.

Ana göreve REVIZYON_03.md üzerinden devam et. Bu notu mutlaka oku.
