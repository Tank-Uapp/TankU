// Supabase Edge Function: ai-recommend
//
// Gathers a tank's profile + recent readings (respecting the caller's RLS)
// and asks Venice AI (OpenAI-compatible API) for reef-keeping recommendations.
// When the app sets include_photos=true, the initial analysis also attaches
// recent tank photos (oldest→newest) so a vision-capable model can assess
// visible progress. It's opt-in so the common case stays cheap and fast.
// The Venice API key lives only in this function's secrets — never in the app.
//
// Deploy:
//   supabase functions deploy ai-recommend
// Set secrets:
//   supabase secrets set VENICE_API_KEY=your_key
//   supabase secrets set VENICE_MODEL=llama-3.3-70b   (optional)
//
// Invoked from the app via supabase.functions.invoke('ai-recommend', ...).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { encodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";

const VENICE_URL = "https://api.venice.ai/api/v1/chat/completions";

// Per-user cap on AI calls per day (each call — the initial analysis and every
// follow-up — counts). Override with the AI_DAILY_LIMIT secret if needed.
const DAILY_LIMIT = Number(Deno.env.get("AI_DAILY_LIMIT") ?? "4");

// How many photos to attach to the initial analysis (sampled evenly across the
// available time range, always including the oldest and newest), and the size
// cap per image so the request to Venice stays reasonable.
const MAX_PHOTOS = 6;
const MAX_PHOTO_BYTES = 5 * 1024 * 1024;

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

type ModelInfo = { id: string; vision: boolean };

/// Lists Venice text models with whether each supports image input (vision).
async function listModels(apiKey: string): Promise<ModelInfo[]> {
  try {
    const res = await fetch("https://api.venice.ai/api/v1/models?type=text", {
      headers: { Authorization: `Bearer ${apiKey}` },
    });
    if (!res.ok) return [];
    const body = await res.json();
    return (body?.data ?? [])
      .map((m: Record<string, unknown>) => ({
        id: m?.id,
        // Venice exposes per-model capabilities under model_spec.capabilities.
        vision: Boolean(
          (m?.model_spec as { capabilities?: { supportsVision?: boolean } })
            ?.capabilities?.supportsVision,
        ),
      }))
      .filter((m: { id?: unknown }): m is ModelInfo => typeof m.id === "string");
  } catch (_) {
    return [];
  }
}

/// Picks a usable model. When [needVision] is set, restricts to vision-capable
/// models. Prefers VENICE_MODEL if valid, then a curated list, then any.
function chooseModel(
  models: ModelInfo[],
  preferred: string | undefined,
  needVision: boolean,
): string | null {
  if (models.length === 0) {
    if (preferred && preferred.length > 0) return preferred;
    // Couldn't read the model list — fall back to a known capable default.
    return needVision ? "mistral-31-24b" : null;
  }
  const pool = needVision ? models.filter((m) => m.vision) : models;
  const ids = pool.map((m) => m.id);
  if (ids.length === 0) return null;
  if (preferred && ids.includes(preferred)) return preferred;
  const prefs = needVision
    ? ["mistral-31-24b", "qwen-2.5-vl"]
    : [
        "llama-3.3-70b",
        "qwen3-235b",
        "llama-3.1-405b",
        "mistral-31-24b",
        "deepseek-r1-671b",
      ];
  for (const p of prefs) {
    if (ids.includes(p)) return p;
  }
  return ids[0];
}

/// Evenly samples up to [max] items, always keeping the first and last.
function sample<T>(arr: T[], max: number): T[] {
  if (arr.length <= max) return arr;
  if (max <= 1) return [arr[0]];
  const out: T[] = [];
  const step = (arr.length - 1) / (max - 1);
  for (let i = 0; i < max; i++) out.push(arr[Math.round(i * step)]);
  return out;
}

function guessImageType(path: string): string {
  const ext = path.split(".").pop()?.toLowerCase();
  switch (ext) {
    case "png":
      return "image/png";
    case "webp":
      return "image/webp";
    case "heic":
      return "image/heic";
    default:
      return "image/jpeg";
  }
}

/// Downloads a private storage object (via the caller's RLS) and returns it as
/// a base64 data URL, or null if it can't be fetched / is too large.
async function toDataUrl(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  path: string,
): Promise<string | null> {
  try {
    const { data, error } = await supabase.storage
      .from("tank-photos")
      .download(path);
    if (error || !data) return null;
    const buf = new Uint8Array(await data.arrayBuffer());
    if (buf.byteLength === 0 || buf.byteLength > MAX_PHOTO_BYTES) return null;
    const type =
      typeof data.type === "string" && data.type.startsWith("image/")
        ? data.type
        : guessImageType(path);
    return `data:${type};base64,${encodeBase64(buf)}`;
  } catch (_) {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader) return json({ error: "Missing Authorization." }, 401);

    const reqBody = await req.json().catch(() => ({}));
    const tank_id = reqBody?.tank_id;
    if (!tank_id) return json({ error: "tank_id is required." }, 400);

    // Opt-in: only attach photos (and use a vision model) when the app asks.
    // Defaults off so the common case stays cheap and fast.
    const includePhotos = reqBody?.include_photos === true;

    // Prior conversation turns from the app (memory). Validated + capped.
    const history: Array<{ role: string; content: string }> =
      Array.isArray(reqBody?.messages)
        ? reqBody.messages
            .filter(
              (m: { role?: string; content?: string }) =>
                (m?.role === "user" || m?.role === "assistant") &&
                typeof m?.content === "string",
            )
            .slice(-20)
        : [];

    // Client bound to the caller's JWT → RLS ensures they only read their tank.
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    // Identify the caller and enforce the per-user daily limit before doing any
    // expensive work. The counter is read/written with the service role so a
    // user can't tamper with it (they only have read access via RLS).
    const { data: userData, error: userErr } = await supabase.auth.getUser();
    const userId = userData?.user?.id;
    if (userErr || !userId) {
      return json({ error: "Not authenticated." }, 401);
    }

    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceKey) {
      return json({ error: "Server is misconfigured (no service role)." }, 500);
    }
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey);

    const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD (UTC)
    const { data: usageRow } = await admin
      .from("ai_usage")
      .select("count")
      .eq("user_id", userId)
      .eq("day", today)
      .maybeSingle();
    const used = usageRow?.count ?? 0;
    if (used >= DAILY_LIMIT) {
      return json(
        {
          error:
            `You've used all ${DAILY_LIMIT} of today's AI questions. ` +
            "Please try again tomorrow.",
          code: "rate_limited",
          usage: { used, limit: DAILY_LIMIT, remaining: 0 },
        },
        429,
      );
    }

    const [
      { data: tank },
      equipment,
      livestock,
      dosing,
      feedings,
      health,
      readings,
      photos,
    ] = await Promise.all([
      supabase.from("tanks").select("*").eq("id", tank_id).single(),
      supabase.from("equipment").select("*").eq("tank_id", tank_id),
      supabase.from("livestock").select("*").eq("tank_id", tank_id),
      supabase.from("dosing").select("*").eq("tank_id", tank_id),
      supabase.from("feedings").select("*").eq("tank_id", tank_id),
      supabase
        .from("health_logs")
        .select("*")
        .eq("tank_id", tank_id)
        .order("observed_at", { ascending: false })
        .limit(20),
      supabase
        .from("parameter_readings")
        .select("*")
        .eq("tank_id", tank_id)
        .order("measured_at", { ascending: false })
        .limit(120),
      supabase
        .from("tank_photos")
        .select("storage_path, taken_on")
        .eq("tank_id", tank_id)
        .order("taken_on", { ascending: false })
        .order("created_at", { ascending: false })
        .limit(40),
    ]);

    if (!tank) return json({ error: "Tank not found or not yours." }, 404);

    // Latest reading per parameter + a short recent history.
    const latest: Record<string, { value: number; measured_at: string }> = {};
    for (const r of readings.data ?? []) {
      if (!latest[r.parameter_key]) {
        latest[r.parameter_key] = { value: r.value, measured_at: r.measured_at };
      }
    }

    const habitat: string = tank.habitat ?? "saltwater";

    // Photo rows newest-first → chronological for "progress over time".
    const photoRows: Array<{ storage_path: string; taken_on: string }> = (
      photos.data ?? []
    ).slice().reverse();

    const context = {
      tank: {
        name: tank.name,
        volume_liters: tank.volume_liters,
        habitat,
        type: tank.tank_type,
        started_on: tank.started_on,
        notes: tank.notes,
      },
      equipment: (equipment.data ?? []).map((e) => ({
        name: e.name,
        category: e.category,
        brand: e.brand,
        model: e.model,
      })),
      livestock: (livestock.data ?? []).map((l) => ({
        name: l.name,
        kind: l.kind,
        species: l.species,
        quantity: l.quantity,
      })),
      dosing: (dosing.data ?? []).map((d) => ({
        product: d.product,
        amount: d.amount,
        unit: d.unit,
        frequency: d.frequency,
        targets: d.target_parameter,
      })),
      feeding: (feedings.data ?? []).map((f) => ({
        food: f.food,
        amount: f.amount,
        frequency: f.frequency,
        notes: f.notes,
      })),
      health_journal: (health.data ?? []).map((h) => ({
        rating_out_of_10: h.rating,
        notes: h.notes,
        at: h.observed_at,
      })),
      latest_readings: latest,
      recent_history: (readings.data ?? []).slice(0, 60).map((r) => ({
        parameter: r.parameter_key,
        value: r.value,
        at: r.measured_at,
      })),
      // Dates of photos on file (the actual images are attached on the first
      // analysis turn for vision models; here so text turns know they exist).
      photo_dates: photoRows.map((p) => p.taken_on),
    };

    // Prefer the standard name; fall back to "TankU" (the name this project's
    // secret was originally saved under).
    const apiKey = Deno.env.get("VENICE_API_KEY") ?? Deno.env.get("TankU");
    if (!apiKey) {
      return json(
        { error: "Venice API key secret is not set (VENICE_API_KEY)." },
        500,
      );
    }

    // Attach photos only on the first analysis (history empty) — follow-ups
    // already have the model's photo read in the conversation, so re-sending
    // images each turn would be wasteful.
    const photoParts: Array<
      | { type: "text"; text: string }
      | { type: "image_url"; image_url: { url: string } }
    > = [];
    if (includePhotos && history.length === 0 && photoRows.length > 0) {
      for (const p of sample(photoRows, MAX_PHOTOS)) {
        const url = await toDataUrl(supabase, p.storage_path);
        if (!url) continue;
        photoParts.push({
          type: "text",
          text: `Tank photo taken ${String(p.taken_on)}:`,
        });
        photoParts.push({ type: "image_url", image_url: { url } });
      }
    }
    const photoCount = photoParts.filter((p) => p.type === "image_url").length;

    const models = await listModels(apiKey);
    const haveModelList = models.length > 0;
    let model = chooseModel(models, Deno.env.get("VENICE_MODEL"), photoCount > 0);
    // If we wanted vision but the chosen model can't do it, drop the images and
    // fall back to a text model so the analysis still runs.
    let sendPhotos = photoCount > 0;
    if (sendPhotos && haveModelList) {
      const modelVision = models.find((m) => m.id === model)?.vision ?? false;
      if (!modelVision) {
        sendPhotos = false;
        model = chooseModel(models, Deno.env.get("VENICE_MODEL"), false);
      }
    }
    if (!model) {
      return json(
        { error: "No suitable Venice model available for this API key." },
        502,
      );
    }

    const ranges: Record<string, string> = {
      saltwater:
        "saltwater reef target ranges (Alk 8-9.5 dKH, Ca 400-450 ppm, " +
        "Mg 1250-1350 ppm, pH 7.9-8.4, NO3 2-10 ppm, PO4 0.03-0.10 ppm, " +
        "temp 24.5-26.5C, salinity 1.025/35ppt)",
      freshwater:
        "freshwater target ranges (pH 6.5-7.5, Ammonia 0, Nitrite 0, " +
        "NO3 <20 ppm, GH 4-12 dGH, KH 3-8 dKH, PO4 <1 ppm, temp 24-27C); " +
        "planted tanks tolerate higher nitrate and benefit from CO2",
      pond:
        "pond/koi target ranges (pH 7.0-8.5, Ammonia 0, Nitrite 0, " +
        "NO3 <40 ppm, KH 4-8 dKH, dissolved O2 6-9 mg/L, PO4 <0.5 ppm); " +
        "watch temperature swings and oxygen in warm weather",
    };

    const advisorRole = habitat === "freshwater"
      ? "freshwater aquarium"
      : habitat === "pond"
      ? "pond and koi"
      : "saltwater reef aquarium";
    const habitatRanges = ranges[habitat] ?? ranges.saltwater;

    const systemPrompt =
      `You are an expert ${advisorRole} advisor. You are given a tank's full ` +
      "profile: volume, habitat and type, equipment, livestock, dosing, " +
      "feeding schedule, the owner's health journal (1-10 ratings + notes), " +
      "the latest water parameters, recent parameter history, and sometimes " +
      "dated photos of the tank. " +
      `This tank's habitat is ${habitat}. Reference common ${habitatRanges}. ` +
      "When dated photos are provided, examine them in chronological order " +
      "(oldest to newest) to judge visible progress — algae growth or " +
      "reduction, coral color and polyp extension, plant growth, water " +
      "clarity, and livestock condition — and weave what you see into your " +
      "analysis, calling out concrete changes between photos. " +
      "For your FIRST analysis of the tank, respond in markdown with these " +
      "sections:\n" +
      "## What's going on — a short read of the tank's overall state and any " +
      "notable trends (improving/declining, swings, correlations between " +
      "parameters, livestock load vs nutrients, feeding vs nitrate/phosphate, " +
      "and visible changes across any photos).\n" +
      "## Watch-outs — anything out of range or risky, most urgent first.\n" +
      "## Suggestions — specific, actionable adjustments (dosing amounts, " +
      "feeding, husbandry, equipment) to improve or maintain the tank.\n" +
      "For any FOLLOW-UP questions, answer directly and conversationally " +
      "(skip the section headers). Always stay concise and practical, tailor " +
      "advice to the actual livestock and data present, and reference the " +
      "target ranges when relevant. If data is sparse, say what to test or log " +
      "next. Remind the user to verify major changes before acting.";

    const dataText =
      "Here is my tank data as JSON:\n\n" +
      JSON.stringify(context, null, 2) +
      (sendPhotos
        ? `\n\nI've also attached ${photoCount} photo(s) of the tank over ` +
          "time, in chronological order (oldest first). Use them to assess " +
          "visible progress and factor it into your analysis."
        : "") +
      "\n\nGive your analysis.";

    const userContent = sendPhotos
      ? [{ type: "text", text: dataText }, ...photoParts]
      : dataText;

    const aiRes = await fetch(VENICE_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userContent },
          // The ongoing conversation (initial analysis, then follow-ups).
          ...history,
        ],
        temperature: 0.4,
        max_tokens: 1100,
      }),
    });

    if (!aiRes.ok) {
      const detail = await aiRes.text();
      return json(
        { error: `Venice AI error (${aiRes.status}): ${detail}` },
        502,
      );
    }

    const data = await aiRes.json();
    const recommendation: string =
      data?.choices?.[0]?.message?.content ?? "No recommendation returned.";

    // Count this successful call. Read-then-write is fine at this volume; a
    // rare race could allow one extra call, never fewer.
    const { data: incRow } = await admin
      .from("ai_usage")
      .upsert(
        {
          user_id: userId,
          day: today,
          count: used + 1,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "user_id,day" },
      )
      .select("count")
      .maybeSingle();
    const newUsed = incRow?.count ?? used + 1;

    return json({
      recommendation,
      usage: {
        used: newUsed,
        limit: DAILY_LIMIT,
        remaining: Math.max(0, DAILY_LIMIT - newUsed),
      },
    });
  } catch (e) {
    return json({ error: `Unexpected error: ${e}` }, 500);
  }
});
