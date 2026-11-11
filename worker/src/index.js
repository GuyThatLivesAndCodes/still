import { TASKS, validTexts, buildMessages } from "./prompts.js";

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
      const result = await env.AI.run(env.MODEL || "@cf/meta/llama-3.1-8b-instruct-fp8-fast", {
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
