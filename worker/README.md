# still. AI Worker

A tiny, stateless Cloudflare Worker that powers **Quiet AI** in still. when the iPhone can't run Apple's on-device model, or when the user picks Cloudflare.

- Four endpoints only: `POST /v1/reflect` (warm note), `POST /v1/openers` (eight prompts), `POST /v1/chat` (reply in a note chat) and `POST /v1/nudge` (one lock-screen-safe reminder line). Body: `{ "texts": ["…"], "profile": "optional, ≤400 chars" }`; chat also takes `"messages": [{ "role": "user" | "assistant", "content": "…" }]` ending with the person. Reply: `{ "text": "…" }`.
- Prompts live on the server (`src/prompts.js`), so it can't be used as a general chatbot.
- Nothing is logged or stored. Observability is off, errors aren't logged, and responses are `no-store`.
- Rate-limited per IP (20/min) and input-capped (16 texts, 4,000 chars each, 12,000 total; 16 chat turns of 1,500 chars).
- Model: `@cf/meta/llama-3.1-8b-instruct-fp8-fast` (change `MODEL` in `wrangler.toml`). One note costs about $0.0001. Workers AI's free 10,000 neurons per day cover roughly 1,000+ requests.

## Deploy

```sh
cd worker
npm install
npx wrangler login
npx wrangler deploy
```

Wrangler prints a URL like `https://still-ai.<your-subdomain>.workers.dev`.

## Or paste it in the dashboard

`dashboard.js` is the same Worker in one file. Create a Worker named `still`, paste it, then in *Settings → Bindings* add **Workers AI** with the name `AI`. A Rate Limiting binding named `LIMITER` is optional.

## Point the app at it

- **Default:** `project.yml` already points at `https://still.zorbyteofficial.workers.dev`.
- **CI override:** in GitHub, go to *Settings → Secrets and variables → Actions → Variables* and add `STILL_AI_ENDPOINT` with that URL. The next **Build IPAs** run bakes it in.
- **Local builds:** set `STILL_AI_ENDPOINT` in `project.yml` (Still target settings), then `xcodegen generate`.

With no endpoint set, the app hides the Cloudflare option and uses only Apple's on-device model.

## Test

```sh
npm test
```
