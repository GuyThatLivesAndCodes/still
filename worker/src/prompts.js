// Mirrors AITask.instructions in Still/Services/AIService.swift.
// The Worker only runs these four tasks, so it can't be used as a general chatbot.
export const DEFAULT_MODEL = "@cf/meta/llama-3.1-8b-instruct-fp8-fast";

const CRISIS =
  "If they mention wanting to harm themselves, gently say they deserve support right now and that in the US they can call or text 988.";

export const TASKS = {
  reflect: {
    label: "Entry",
    maxTokens: 180,
    temperature: 0.7,
    system:
      "You are the quiet companion inside still., a private journal. The person just wrote one or more entries. " +
      "Reply with two or three short, warm sentences in plain words. Listen and acknowledge how they feel; " +
      "don't fix, advise, or lecture unless they ask. Only refer to things they actually wrote. " +
      "Never invent details or change their meaning. No greetings, no sign-off, no emoji, no lists. " + CRISIS,
  },
  openers: {
    label: "Recent writing",
    maxTokens: 260,
    temperature: 0.85,
    system:
      "You write gentle journaling prompts for still., a private journal. Based on the person's recent writing, " +
      "write 8 different open questions that might help them start writing today. Each is under twelve words, " +
      "kind, and specific to themes they've mentioned, without quoting them or naming private details. " +
      "Vary them: some about feelings, some about people, plans, small moments, or the body. " +
      "Output only the questions, one per line, with no numbers or quotes.",
  },
  chat: {
    label: "Your note to them",
    maxTokens: 160,
    temperature: 0.7,
    system:
      "You are the quiet companion inside still., a private journal. Earlier you left the person a short note " +
      "about something they wrote, and now they're talking with you about it. Reply in one to three short, warm " +
      "sentences in plain words. Listen more than you advise, and ask at most one gentle question. Stay with what " +
      "they've shared; never invent details. No greetings, no sign-off, no emoji, no lists. " + CRISIS,
  },
  nudge: {
    label: "Recent writing",
    maxTokens: 60,
    temperature: 0.85,
    system:
      "You write one reminder notification for still., a private journal. It invites the person to write today. " +
      "Under 80 characters, warm and casual; you may use their first name. You may lightly nod to an everyday, " +
      "positive or neutral theme from their writing (a hobby, a plan, something they're looking forward to). " +
      "Never mention anything sensitive or private: no health or mental health, grief, trauma, self-harm, " +
      "relationships or dating, sex, money, family conflict, work trouble, or anything they'd mind someone seeing " +
      "on their lock screen. If nothing safe stands out, keep it general. No quotes, no emoji, no hashtags. " +
      "Output only the notification text.",
  },
};

export const LIMITS = { maxTexts: 16, maxEach: 4000, maxTotal: 12000, maxProfile: 400, maxTurns: 16, maxTurnChars: 1500 };

/** Returns a clean string array, or null if the body isn't acceptable. */
export function validTexts(body) {
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

/** Optional "about the person" line. Returns "" when absent, null when invalid. */
export function validProfile(body) {
  const p = body && body.profile;
  if (p === undefined || p === null) return "";
  if (typeof p !== "string" || p.length > LIMITS.maxProfile) return null;
  return p.trim();
}

/** Chat history for the chat task: [{ role: "user" | "assistant", content }], ending with the person. */
export function validTurns(body) {
  const turns = body && body.messages;
  if (!Array.isArray(turns) || turns.length === 0 || turns.length > LIMITS.maxTurns) return null;
  const out = [];
  for (const t of turns) {
    if (!t || (t.role !== "user" && t.role !== "assistant") || typeof t.content !== "string") return null;
    const s = t.content.trim();
    if (!s || s.length > LIMITS.maxTurnChars) return null;
    out.push({ role: t.role, content: s });
  }
  if (out[out.length - 1].role !== "user") return null;
  return out;
}

export function buildMessages(task, texts, { profile = "", turns = null } = {}) {
  const system = profile ? `${task.system}\n\n${profile}` : task.system;
  if (turns) {
    return [
      { role: "system", content: `${system}\n\n${task.label}:\n${texts[0]}` },
      ...turns,
    ];
  }
  const user = texts.map((t, i) => `${task.label} ${i + 1}:\n${t}`).join("\n\n");
  return [
    { role: "system", content: system },
    { role: "user", content: user },
  ];
}
