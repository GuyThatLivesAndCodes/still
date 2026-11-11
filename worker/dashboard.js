// still. Quiet AI Worker, single file for the Cloudflare dashboard.
// Setup: Settings > Bindings > add "Workers AI" named AI.
// Optional: a Rate Limiting binding named LIMITER, and a MODEL variable.
const DEFAULT_MODEL = "@cf/meta/llama-3.1-8b-instruct-fp8-fast";

// Mirrors AITask.instructions in Still/Services/AIService.swift.
// The Worker only runs these two tasks, so it can't be used as a general chatbot.
const TASKS = {
  reflect: {
    label: "Entry",
    maxTokens: 180,
    system:
      "You are the quiet companion inside still., a private journal. The person just wrote one or more entries. " +
      "Reply with two or three short, warm sentences in plain words. Listen and acknowledge how they feel; " +
      "don't fix, advise, or lecture unless they ask. Only refer to things they actually wrote. " +
      "Never invent details or change their meaning. No greetings, no sign-off, no emoji, no lists. " +
      "If they mention wanting to harm themselves, gently say they deserve support right now and that in the US they can call or text 988.",
  },
  openers: {
    label: "Recent writing",
    maxTokens: 120,
    system:
      "You write gentle journaling prompts for still., a private journal. Based on the person's recent writing, " +
      "write four different open questions that might help them start writing today. Each is under twelve words, " +
      "kind, and specific to themes they've mentioned, without quoting them or naming private details. " +
      "Output only the four questions, one per line, with no numbers or quotes.",
  },
};

const LIMITS = { maxTexts: 10, maxEach: 4000, maxTotal: 12000 };

/** Returns a clean string array, or null if the body isn't acceptable. */
function validTexts(body) {
  const texts = body && body.texts;
  if (!Array.isArray(texts) || texts.length === 0 || texts.length > LIMITS.maxTexts) return null;
  let total = 0;
  const out = [];
  for (const t of texts) {
    if (typeof t !== "string") return null;
    const s = t.trim();
    if (!s) continue;
    if (s.length > LIMITS.maxEach) return null;
    total += s.length;
    out.push(s);
  }
  if (out.length === 0 || total > LIMITS.maxTotal) return null;
  return out;
}

function buildMessages(task, texts) {
  const user = texts.map((t, i) => `${task.label} ${i + 1}:\n${t}`).join("\n\n");
  return [
    { role: "system", content: task.system },
    { role: "user", content: user },
  ];
}


// Stateless: nothing is logged, stored, or cached. The request body only lives
// for the length of this function call.
const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const match = url.pathname.match(/^\/v1\/(reflect|openers)$/);
    if (!match) return json({ error: "not_found" }, 404);
    if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

    const ip = request.headers.get("cf-connecting-ip") || "unknown";
    if (env.LIMITER) {
      const { success } = await env.LIMITER.limit({ key: ip });
      if (!success) return json({ error: "rate_limited" }, 429);
    }

    if (Number(request.headers.get("content-length") || 0) > 64 * 1024) {
      return json({ error: "too_large" }, 413);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "bad_json" }, 400);
    }
    const texts = validTexts(body);
    if (!texts) return json({ error: "bad_request" }, 400);

    const task = TASKS[match[1]];
    try {
      const result = await env.AI.run(env.MODEL || DEFAULT_MODEL, {
        messages: buildMessages(task, texts),
        max_tokens: task.maxTokens,
        temperature: 0.7,
      });
      const text = (result && (result.response ?? result.choices?.[0]?.message?.content)) || "";
      if (!text.trim()) return json({ error: "empty" }, 502);
      return json({ text: text.trim() });
    } catch {
      // Deliberately no logging of the error, which could include input.
      return json({ error: "model_error" }, 502);
    }
  },
};
