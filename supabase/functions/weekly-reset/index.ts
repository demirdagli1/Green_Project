// supabase/functions/weekly-reset/index.ts
// Haftalık sıfırlama ve şampiyon belirleme Edge Function'ı.
// JWT doğrulaması ve server_admins kontrolü içerir.
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
      throw new Error("Sunucu ortam değişkenleri (URL/SERVICE_KEY) eksik");
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
        return new Response(JSON.stringify({ ok: false, error: "Yetersiz yetki: Yalnızca yöneticiler haftalık sıfırlama yapabilir." }), {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    // Privileged client with service_role key calls atomic weekly reset RPC
    const { data, error } = await supabase.rpc("rpc_admin_trigger_weekly_reset");

    if (error) {
      return new Response(JSON.stringify({ ok: false, error: error.message }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ ok: true, result: data }), {
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
