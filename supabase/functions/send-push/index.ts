// supabase/functions/send-push/index.ts
// Yeşil Adım Canlı Realtime Bildirim Dağıtımı (admin_notifications_log kanalı üzerinden Realtime yayın).
// DİKKAT: Bu fonksiyon harici bir FCM/APNs arka plan bildirim servisi DEĞİLDİR;
// doğrudan veritabanındaki admin_notifications_log kuyruğuna yazarak aktif açık
// mobil istemcilerin Supabase Realtime aboneliğini tetikler.
// Deno / Supabase Edge Runtime uyumlu.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error("Sunucu ortam değişkenleri eksik");
    }

    // Yetki Kontrolü: Authorization başlığı zorunludur
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ ok: false, error: "Yetkisiz erişim: Authorization başlığı eksik." }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace(/^Bearer\s+/i, "");
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Eğer doğrudan service_role key ile çağrılmamışsa, kullanıcının admin olduğunu doğrula
    if (token !== supabaseServiceKey) {
      const { data: { user }, error: userError } = await supabase.auth.getUser(token);
      if (userError || !user) {
        return new Response(JSON.stringify({ ok: false, error: "Geçersiz kimlik oturumu." }), {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const { data: adminRow } = await supabase
        .from("server_admins")
        .select("user_id")
        .eq("user_id", user.id)
        .maybeSingle();

      if (!adminRow) {
        return new Response(JSON.stringify({ ok: false, error: "Yetersiz yetki: Yalnızca yöneticiler bildirim gönderebilir." }), {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    const { target_type, target_user_id, target_clan_id, template_code, title, message_body, severity } =
      await req.json();

    const { data, error } = await supabase.rpc("rpc_admin_send_notification", {
      p_target_type: target_type || "all",
      p_target_user_id: target_user_id || null,
      p_target_clan_id: target_clan_id || null,
      p_template_code: template_code || null,
      p_title: title || "Yeşil Adım Bildirimi",
      p_message_body: message_body || "",
      p_severity: severity || "savage",
    });

    if (error) {
      return new Response(JSON.stringify({ ok: false, error: error.message }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({
      ok: true,
      delivery_mode: "supabase_realtime_broadcast",
      notification: data
    }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ ok: false, error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
