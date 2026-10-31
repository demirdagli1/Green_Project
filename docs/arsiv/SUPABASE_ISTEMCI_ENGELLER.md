# Supabase İstemci Engeller ve Root Talepleri

**Tarih:** 31 Ekim 2026  
**Kimden:** Supabase İstemci Entegrasyon Ajanı  
**Kime:** Root & Backend İnceleme Ajanı  

---

### 1. Root MCP Şema Dağıtımı (Açık Bekleyen)
- **Durum:** İstemci tarafı tüm RPC sözleşmeleriyle (`rpc_sync_initial_profile`, `rpc_record_steps`, `rpc_record_transit`, `rpc_record_bike`, `rpc_record_vehicle_penalty`, `rpc_buy_shop_item`, `rpc_equip_shop_item`, `rpc_join_clan`) ve görünümleriyle (`v_leaderboard_users`, `v_clan_leaderboard`, vb.) tam uyumlu olarak hazırlanmış ve 114 testle doğrulanmıştır.
- **Root Adımı:** Root ajanı `supabase/full_deployment.sql` dosyasını MCP `execute_sql` ile canlı projeye (`fhaxxraibydsjikxacbb`) dağıtmalıdır. Dağıtım öncesinde istemci şeffaf fallback ve kuyruklama modunda çalışır.

### 2. Avatar Storage Bucket Sözleşmesi
- **Durum:** İstemci, kullanıcının seçtiği yerel fotoğrafı (`/data/user/0/...`) başka cihazlara dosya yolu olarak göndermez. İstemcide `avatars` bucket'ına (`$userId/avatar.png`) yükleme mekanizması hazırdır.
- **Backend İhtiyacı:** Backend inceleme ajanı `avatars` bucket'ı için RLS politikasını (klasör sahibi `auth.uid()` için upload/overwrite izni, public okuma) tamamlayıp şemaya eklemelidir. Storage henüz aktif değilken yerel profil fotoğrafı cihazda korunur, uzak cihaza kırık yol gönderilmez.

### 3. Transit Cooldown Sözleşmesi (45 Dakika)
- **Durum:** İstemci tarafı hem QR hem de NFC binişlerinde 45 dakikalık ortak cooldown kuralını uygulamaktadır. Backend RPC fonksiyonunda (`rpc_record_transit`) daha önce sehven 15 dakika yazılan sürenin 45 dakika ile tutarlı deploy edilmesi teyit edilmelidir.
