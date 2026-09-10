# Habenula Console

A local web GUI for a running [Habenula](https://habenula.ai) engine. It shows
**real** held calls and answers them, and covers the rest of the CLI's read and
write surface in one page: grants, spending caps, services, tasks, policy, the
audit log, the kill switch, and engine lifecycle.

Nothing here is simulated. Every panel is a live read off the engine's HTTP
API, and answering a hold is a `POST /api/resolve` that mints a real grant and
writes a real entry to the hash-chained audit log. Verify it yourself with
`habenula log verify`.

## Run it

```bash
cd console
npm start            # → http://127.0.0.1:7676
```

No dependencies — Node's standard library only. Node >= 22.22.1.

The engine does not need to be running first; if none is, the console says so
loudly and offers to start one.

| Env var | Default | Notes |
|---|---|---|
| `CONSOLE_PORT` | `7676` | Port this console listens on. |
| `HABENULA_USER_ID` | `cli-user` | **The one that bites.** The CLI defaults to `cli-user`; the engine's own fallback is `demo-user`. A mismatch is not an error — it is a different Durable Object, so the queue reads as permanently empty. Shown in the header for exactly that reason. |
| `HABENULA_URL` | discovery | Pin the engine, e.g. `http://127.0.0.1:8787`, to skip the port walk. |

## Why the browser never talks to the engine

All engine traffic runs in `server.mjs`, for two reasons:

- **The loopback guard.** The engine rejects a request whose `Origin` is not
  loopback. A browser page always sends one; Node's `fetch` sends none, which
  passes. Proxying server-side sidesteps the problem rather than weakening the
  guard.
- **Discovery and lifecycle are process work, not API calls.** Reading the port
  out of `~/.habenula/config`, walking 8787–8796, and running `up`/`down` are
  not things a page can do.

As a side effect the page never learns the engine URL, and can only do the
handful of things `/api/do/*` exposes.

## One poller, any number of tabs

The server polls; browsers subscribe over SSE. Ten open tabs cost the engine
exactly what one costs.

- **Status every tick** — it carries the parked calls, so it must be fresh.
- **Everything else on a longer stride** (every fifth tick). Re-reading caps,
  policy, services, catalog and tasks every tick would multiply engine load by
  six for no new information.
- **Adaptive cadence** — 1s while a decision is parked or a tab is focused, 4s
  when idle, 5s backoff while rediscovering.
- **Push only on change.** State is hashed each tick; an unanswered hold does
  not repaint sixty times a minute.
- **Prompt refresh after a mutation** rather than waiting out the interval.

## Agent-supplied text is untrusted

Every string in a held call was chosen by an agent — the recipient of an email,
a goal, a parameter value. All of it is escaped, length-clamped, and scanned
for characters that could misrepresent the permission: control characters,
zero-width characters, bidi overrides, and line separators.

Those are **flagged, not silently stripped**, and replaced with a visible `␣`.
A hidden character removed without comment is a changed meaning you cannot see.

A recipient of `sam@example.com<U+202E><U+200B>evil@attacker.test` renders as
the visible text plus `zero-width character` and `bidi override` badges, in the
queue and in the audit log alike.

## What it deliberately doesn't do

- **It never auto-dismisses a pending decision.** The agent is parked and
  waiting; a request that vanishes because you looked away is the failure mode,
  not the tidy default.
- **It treats an unreachable engine as a loud state**, not a quiet empty queue.
  That is the one condition where you believe you are protected and are not, so
  it gets a red card naming which ports were tried — and every other panel is
  dimmed and stamped `last known`, because leaving stale reads looking live is
  the same lie in a quieter voice.
- **It never offers a button the engine will reject.** A spend hold takes
  `approve_once` and refuses the grant-minting choices; an ordinary hold is the
  reverse. The engine enforces this, so the UI matches it rather than
  discovering it through a 400.
- **It holds no credentials and makes no policy decision.** Every decision is
  the engine's. This is a view and a set of buttons.
- **It does not pretend policy is editable.** The engine exposes no
  policy-write route, so the panel is read-only and says so. Caps are writable,
  and those are.

## Keyboard triage

The numbers match the CLI's confirmation prompt, so the muscle memory carries
over.

| Key | Action |
|---|---|
| <kbd>j</kbd> / <kbd>k</kbd> | move between parked calls |
| <kbd>1</kbd> | deny |
| <kbd>2</kbd> | what is this? (returns tool metadata, stays parked) |
| <kbd>3</kbd> | allow for this task |
| <kbd>4</kbd> | allow for this session |

## The branches that strand a naive client

Each is handled by name, and in every one **the call stays parked** — the row
does not vanish and imply a decision was reached.

| | |
|---|---|
| `404` | the hold expired or was already answered |
| `409` | a turn is already in progress for that task |
| `400` | that choice is wrong for this hold's kind |
| engine gone | rediscovery, not a hammering retry against a dead port |

## Security boundary

The engine is unauthenticated on loopback in this release, by design; the
machine is the trust boundary. **This server is unauthenticated too**, and it
can start and stop the engine and answer holds. It binds `127.0.0.1` and
nothing else. Do not expose either port.

## Coverage

| CLI verb | Console |
|---|---|
| `status` | header + grants + queue |
| `resolve` (the confirmation prompt) | the queue, keyboard-first |
| `kill` | header |
| `quit` | header |
| `up` / `down` | header, and the unreachable banner |
| `connect` / `disconnect` | Services panel, both tabs |
| `cap` | Spending caps, read and write |
| `policy list` | Policy panel, read-only |
| `task` (list, cancel) | Tasks panel |
| `log`, `log verify` | Audit log, cursor-paged |
| `chat` | **not yet** — see below |

`chat` drives `/internal/mcp` with `INTERNAL_MCP_TOKEN`, needs streaming, and
needs a model backend configured. It is a milestone of its own; bolting on a
half-working conversation pane would make the rest feel like a prototype again.
