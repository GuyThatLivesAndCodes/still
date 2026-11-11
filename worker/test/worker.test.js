import { test } from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";

const env = (reply = { response: "That sounds heavy. It makes sense you're tired." }) => ({
  MODEL: "test-model",
  AI: { run: async (model, input) => { env.last = { model, input }; return reply; } },
  LIMITER: { limit: async () => ({ success: true }) },
});

const post = (path, body) =>
  new Request(`https://x.dev${path}`, { method: "POST", body: JSON.stringify(body), headers: { "content-type": "application/json" } });

test("reflect returns text", async () => {
  const e = env();
  const res = await worker.fetch(post("/v1/reflect", { texts: ["Long day."] }), e);
  assert.equal(res.status, 200);
  assert.match((await res.json()).text, /heavy/);
});

test("rejects unknown paths and bad bodies", async () => {
  assert.equal((await worker.fetch(post("/v1/chat", { texts: ["hi"] }), env())).status, 404);
  assert.equal((await worker.fetch(post("/v1/reflect", { texts: [] }), env())).status, 400);
  assert.equal((await worker.fetch(post("/v1/reflect", { texts: ["x".repeat(5000)] }), env())).status, 400);
  assert.equal((await worker.fetch(new Request("https://x.dev/v1/reflect"), env())).status, 405);
});

test("rate limited", async () => {
  const e = env();
  e.LIMITER.limit = async () => ({ success: false });
  assert.equal((await worker.fetch(post("/v1/openers", { texts: ["a"] }), e)).status, 429);
});

test("model failure is a 502", async () => {
  const e = env();
  e.AI.run = async () => { throw new Error("boom"); };
  assert.equal((await worker.fetch(post("/v1/reflect", { texts: ["a"] }), e)).status, 502);
});
