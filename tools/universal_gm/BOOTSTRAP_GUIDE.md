# Evrensel GM Paneli — Tek Seferlik Güvenli Yönetici Kurulum Kılavuzu

Bu kılavuz, Root yöneticisinin PC tarayıcısından çalışan Evrensel GM Paneli'ne (`tools/universal_gm/index.html`) **kesinlikle `service_role` gizli anahtarı kullanmadan ve sır açığa çıkarmadan** yönetici yetkisi atamasını açıklar.

---

## 1. Mimari ve Güvenlik Modeli

* **Yetkilendirme Katmanı:** Veritabanı seviyesinde `public.server_admins` tablosu üzerinden doğrulanır (`auth.uid()`).
* **İstemci Güvenliği:** Panel yalnızca kamusal `anon` key ve yöneticinin standart `authenticated` JWT oturumunu kullanır. Gizli anahtar veya `service_role` asla istemcide tutulmaz.
* **Denetim İzi:** Yapılan tüm işlemler kimin ne zaman hangi değişikliği yaptığıyla birlikte `public.admin_audit_trail` tablosuna atomik olarak kaydedilir.

---

## 2. Tek Seferlik Kurulum Adımları (Root Tarafından)

### Adım 1: Yönetici Kullanıcısını Oluşturma (Supabase Dashboard)
1. Supabase Dashboard -> **Authentication** -> **Users** sayfasına gidin.
2. **Add User** butonuna tıklayın:
   - **Email:** `admin@yesiladim.local` (veya dilediğiniz bir e-posta)
   - **Password:** Güçlü bir yönetici parolası belirleyin
   - **Auto Confirm:** Açık (Checked)
3. Oluşturulan kullanıcının **User UID** değerini kopyalayın (Örn: `11111111-2222-3333-4444-555555555555`).

### Adım 2: Yöneticiyi `server_admins` Tablosuna Kaydetme (SQL Editor)
Supabase Dashboard -> **SQL Editor** sayfasına gidin ve aşağıdaki tek satırlık SQL'i çalıştırın:

```sql
INSERT INTO public.server_admins (user_id, notes)
VALUES ('<KOPYALANAN_USER_UID>', 'PC GM Web Panel Yöneticisi')
ON CONFLICT (user_id) DO NOTHING;
```

---

## 3. Paneli Çalıştırma ve Giriş Yapma

1. Bilgisayarınızda `tools/universal_gm/` dizininde yerel basit bir HTTP sunucusu açın veya doğrudan dosyayı tarayıcıda açın:
   ```bash
   python3 -m http.server 8080 --directory tools/universal_gm
   ```
2. Tarayıcıda `http://localhost:8080` adresine gidin.
3. Açılan sayfadaki **Yönetici E-Posta** ve **Şifre** alanlarına Adım 1'de belirlediğiniz bilgileri girip **"🔑 E-Posta ile Giriş Yap"** butonuna basın.
4. Panel, Supabase Auth REST servisiyle oturum açarak JWT token'ınızı yerel tarayıcı hafızasına (`localStorage`) güvenle kaydeder.
5. Sol panelden istediğiniz kullanıcıyı seçerek adım, altın, streak ve haftalık puan atayabilir; utanç mesajı kotasını sıfırlayabilirsiniz.

> [!NOTE]
> Herhangi bir `.env` veya `config.local.json` dosyası oluşturulursa bunlar `.gitignore` tarafından otomatik olarak yok sayılır; tokenlar ve kimlik bilgileri repoya sızmaz.
