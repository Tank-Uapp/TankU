// Supabase Edge Function: delete-account
//
// Permanently deletes the calling user's account and all their data. Deleting
// the auth.users row cascades every table that references it (tanks and their
// child rows, health logs, tank_photos rows, ai_usage, custom parameter types).
// The only thing cascade can't reach is the image files in the tank-photos
// storage bucket, so we remove those explicitly first.
//
// Requires the service role, which is why this lives server-side and never in
// the app. Supabase injects SUPABASE_SERVICE_ROLE_KEY into the function env.
//
// Deploy:
//   supabase functions deploy delete-account
//
// Invoked from the app via supabase.functions.invoke('delete-account').

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader) return json({ error: "Missing Authorization." }, 401);

    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceKey) {
      return json({ error: "Server is misconfigured (no service role)." }, 500);
    }

    // Caller-scoped client (RLS) to identify the user and list their own data.
    const caller = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await caller.auth.getUser();
    const userId = userData?.user?.id;
    if (userErr || !userId) return json({ error: "Not authenticated." }, 401);

    const admin = createClient(url, serviceKey);

    // 1. Remove the user's photo files from storage. RLS scopes this select to
    //    the caller's own tanks, so we only ever touch their paths.
    const { data: photoRows } = await caller
      .from("tank_photos")
      .select("storage_path");
    const paths = (photoRows ?? [])
      .map((r: { storage_path?: unknown }) => r.storage_path)
      .filter((p: unknown): p is string => typeof p === "string");
    for (let i = 0; i < paths.length; i += 100) {
      const chunk = paths.slice(i, i + 100);
      if (chunk.length > 0) {
        await admin.storage.from("tank-photos").remove(chunk);
      }
    }

    // 2. Delete the auth user → cascades all their database rows.
    const { error: delErr } = await admin.auth.admin.deleteUser(userId);
    if (delErr) {
      return json({ error: `Could not delete account: ${delErr.message}` }, 500);
    }

    return json({ ok: true });
  } catch (e) {
    return json({ error: `Unexpected error: ${e}` }, 500);
  }
});
