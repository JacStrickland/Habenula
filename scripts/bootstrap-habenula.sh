#!/usr/bin/env bash
# Install Habenula (https://github.com/habenula-ai/habenula-oss) and bring the
# local engine up. Idempotent: safe to re-run.
#
# The engine binds loopback only and has no authentication yet, so the local
# machine is the trust boundary. Never publish its port to a network.
set -euo pipefail

NODE_MIN="22.22.1"

log() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# --- prerequisites ----------------------------------------------------------
command -v node >/dev/null 2>&1 || die "node is not installed (need >= ${NODE_MIN})"
command -v npm  >/dev/null 2>&1 || die "npm is not installed"

node_version="$(node --version | sed 's/^v//')"
lowest="$(printf '%s\n%s\n' "$NODE_MIN" "$node_version" | sort -V | head -1)"
[ "$lowest" = "$NODE_MIN" ] || die "node ${node_version} is too old; Habenula needs >= ${NODE_MIN}"
log "node ${node_version} OK"

# --- headless accommodation -------------------------------------------------
# `habenula connect <service>` spawns xdg-open for the OAuth consent page and
# dies with an unhandled ENOENT when it is absent. On a headless host, print
# the URL instead so the flow stays alive and can be completed by hand.
if ! command -v xdg-open >/dev/null 2>&1; then
  log "no xdg-open found; installing a headless shim"
  install_dir=/usr/local/bin
  [ -w "$install_dir" ] || install_dir="$HOME/.local/bin"
  mkdir -p "$install_dir"
  cat > "$install_dir/xdg-open" <<'SHIM'
#!/bin/sh
echo "xdg-open (headless): $*"
SHIM
  chmod +x "$install_dir/xdg-open"
  case ":$PATH:" in
    *":$install_dir:"*) ;;
    *) log "add $install_dir to PATH so the shim is found" ;;
  esac
fi

# --- install ----------------------------------------------------------------
# `habenula` is the unscoped front door: it pins the CLI and the engine as
# exact dependencies, so one resolution installs the whole product and `up`
# starts the engine from that same install.
log "installing the habenula package globally"
npm install -g habenula

log "verifying npm provenance attestations"
npm audit signatures --include-attestations 2>&1 | tail -5 || \
  log "provenance check reported issues above — review before trusting the install"

# --- start ------------------------------------------------------------------
# First run generates ~/.habenula/config with the credential encryption key and
# the internal MCP token.
log "starting the engine"
habenula up

log "engine state:"
habenula status || true

cat <<'NEXT'

Habenula is installed and the engine is running.

Back up ~/.habenula/config now. Without its CREDENTIAL_ENCRYPTION_KEY, every
credential Habenula has stored becomes unreadable — there is no recovery path.

A conversation still needs a model backend. Pick one and add it to
~/.habenula/config, then re-run `habenula down && habenula up`:

  Anthropic:
    ANTHROPIC_API_KEY=sk-ant-...

  Any OpenAI-compatible endpoint (Ollama, llama.cpp, vLLM, a hosted gateway):
    LLM_PROVIDER=openai-compatible
    LLM_ENDPOINT=http://localhost:11434/v1
    LLM_MODEL=qwen2.5:7b
    LLM_API_KEY=            # only if the backend requires one

Then:
  habenula                 # open the governed conversation
  habenula connect gmail   # connect a service (needs an OAuth client pair)
  habenula log verify      # recompute the audit chain
  habenula kill            # clear every grant at once
  habenula down            # stop the engine
NEXT
