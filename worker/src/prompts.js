// Mirrors AITask.instructions in Still/Services/AIService.swift.
// The Worker only runs these two tasks, so it can't be used as a general chatbot.
export const TASKS = {
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

export const LIMITS = { maxTexts: 10, maxEach: 4000, maxTotal: 12000 };

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

export function buildMessages(task, texts) {
  const user = texts.map((t, i) => `${task.label} ${i + 1}:\n${t}`).join("\n\n");
  return [
    { role: "system", content: task.system },
    { role: "user", content: user },
  ];
}
