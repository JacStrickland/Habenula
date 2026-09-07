# Habenula — local setup

Setup notes and a bootstrap script for [Habenula](https://habenula.ai), the
personal agent control harness
([habenula-ai/habenula-oss](https://github.com/habenula-ai/habenula-oss)).

Habenula governs what an agent *does*: every consequential action is checked
against your rules by a pure function, written to a SHA-256 hash-chained
append-only log before it runs, and executed only with authority you granted.
`habenula kill` revokes all of it at once.

## Install

```bash
./scripts/bootstrap-habenula.sh
```

The script checks prerequisites, installs the `habenula` npm package globally,
verifies provenance, starts the engine, and prints the model-backend step. It
is idempotent.

To do it by hand instead:

```bash
npm install -g habenula   # or use npx habenula, no install
habenula up               # start the engine; generates ~/.habenula/config
habenula                  # open the governed conversation
habenula down             # stop the engine
```

Requires Node >= 22.22.1.

## Back up `~/.habenula/config`

The first `habenula up` generates this file. It holds
`CREDENTIAL_ENCRYPTION_KEY` — the AES-256 key for every credential Habenula
stores. **Without it those credentials cannot be read again, and there is no
recovery path.** Back it up somewhere you control before connecting any real
service.

## Model backend

`habenula up` starts the engine, but a *conversation* needs a model. Nothing is
configured by default, and `habenula` will fail on the first turn until one is.
Add one of these to `~/.habenula/config`, then `habenula down && habenula up`:

```ini
# Anthropic (the default provider)
ANTHROPIC_API_KEY=sk-ant-...
```

```ini
# Any OpenAI-compatible endpoint — Ollama, llama.cpp, vLLM, a hosted gateway.
# LLM_ENDPOINT is the base URL; /chat/completions is appended.
LLM_PROVIDER=openai-compatible
LLM_ENDPOINT=http://localhost:11434/v1
LLM_MODEL=qwen2.5:7b
LLM_API_KEY=
```

Every variable is read at startup, so restart the engine after any change.

The governance loop itself needs no model key — the `mock_email` connector
exercises the full hold → approve → execute → audit path on canned data.

## Connecting services

```bash
habenula connect                # list connectable services
habenula connect mock_email     # the onboarding sandbox, no OAuth app needed
```

Real services (`gmail`, `google_calendar`, `outlook_mail`, `slack`, `github`)
need an OAuth client pair for their provider in `~/.habenula/config` —
`GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` and so on. One pair authorizes the
whole provider, so one Google client covers both Gmail and Calendar.

`connect` opens the consent page with `xdg-open`. On a headless host that
binary is usually absent and the CLI dies with an unhandled `ENOENT`; the
bootstrap script installs a shim that prints the URL instead, so you can paste
it into a browser yourself.

## Everyday commands

| Command | What it does |
|---|---|
| `habenula` | open the governed conversation |
| `habenula status` | active session, connected services, grants, pending holds |
| `habenula policy list` | the standing policy entries |
| `habenula cap --monthly 50 --session 20` | spending caps, in dollars |
| `habenula log` / `habenula log verify` | read the audit log; recompute the chain |
| `habenula kill` | clear every grant, set policy to deny |
| `habenula quit` | end the session; grants expire, connections kept |
| `habenula down` | stop the engine |

## How a governed action looks

With the default `deny` policy, a consequential call holds:

```
mock_email · send · "sam@example.com"
  1. Deny   2. Tell me more   3. Allow for this task   4. Allow for this session
```

The permission is a service, a verb, and the exact target. A different
recipient is a different permission, so it asks again — there is no
"always allow". The audit log records the parameter *shapes*, not their
contents:

```
✓ allow · success  mock_email · send · "sam@example.com"
  params "{\"to\":{\"type\":\"array\",\"length\":1}, ...}"
```

`habenula log verify` recomputes the whole chain locally.

## Security boundary

The engine runs on loopback and **has no authentication yet** (early alpha).
The local machine is the trust boundary. Never publish port 8787 to a network.
For the container path, see
[SELF-HOSTING.md](https://github.com/habenula-ai/habenula-oss/blob/main/SELF-HOSTING.md).

`DEBUG_MODE=true` serves `POST /api/tools/execute`, which drives one governed
call with no conversation behind it. It is a debugging surface — leave it off.

## Running from source

For reading or modifying the code (not the self-hosting path — it runs the
engine under Miniflare):

```bash
git clone https://github.com/habenula-ai/habenula-oss.git
cd habenula-oss
mise install          # installs the pinned node and just
npm ci
just dev              # engine + CLI
just pre-commit       # lint, typecheck, test across all eight packages
```

Source config lives in `packages/engine/.dev.vars` (see `.dev.vars.example`),
not `~/.habenula/config`.

## Upstream

- Repository: <https://github.com/habenula-ai/habenula-oss>
- Install reference: [INSTALL.md](https://github.com/habenula-ai/habenula-oss/blob/main/INSTALL.md)
- Self-host runbook: [SELF-HOSTING.md](https://github.com/habenula-ai/habenula-oss/blob/main/SELF-HOSTING.md)
- Security policy: [SECURITY.md](https://github.com/habenula-ai/habenula-oss/blob/main/SECURITY.md)

Code is AGPL-3.0-only except `packages/audit` (MIT); docs CC BY 4.0.
