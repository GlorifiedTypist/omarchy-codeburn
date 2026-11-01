#!/usr/bin/env bash
set -eo pipefail

# Export environment paths so mise/nvm/bun/user tools are resolved when executed by Quickshell.
# ~/.local/bin is ahead of the inherited PATH so a user install of the fork wins over /usr/local.
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH:/usr/local/bin:/usr/bin"

PERIOD="${1:-today}"

# Whitelist allowed period values to ensure safe argument passing.
case "$PERIOD" in
  today|week|30days|month|all|lifetime) ;;
  *) PERIOD="today" ;;
esac

ARGS=(status --format menubar-json --period "$PERIOD" --no-optimize --no-timeline)

# GlorifiedTypist/codeburn revision that adds the top-level menubar-json `deepseek` object.
# This script does not clone or npx that git URL. The package bin is dist/cli.js, dist/ is
# gitignored, and there is no prepare script, so `npx github:GlorifiedTypist/codeburn` cannot
# start. Install a build (README) and let the lookup below find it.
CODEBURN_FORK_COMMIT="f386bc65f2c4af6bb15932bb056ff5aab0297fca"

fail() {
  printf '%s\n' "$1"
  exit 1
}

# Run a checkout of the fork. Prefer the production bundle; otherwise the repo's dev entry
# (`npm run dev` is `node --import tsx src/cli.ts`) when dependencies are installed.
try_checkout() {
  local dir="$1"
  if [[ -z "$dir" || ! -d "$dir" ]]; then
    return 1
  fi
  if [[ -f "$dir/dist/cli.js" && -f "$dir/dist/main.js" ]]; then
    if ! command -v node >/dev/null 2>&1; then
      fail '{"error":"Node.js was not found on PATH. The CodeBurn fork needs Node.js >= 22.13."}'
    fi
    exec node "$dir/dist/cli.js" "${ARGS[@]}"
  fi
  if [[ -f "$dir/src/cli.ts" && -d "$dir/node_modules/tsx" ]]; then
    if ! command -v node >/dev/null 2>&1; then
      fail '{"error":"Node.js was not found on PATH. The CodeBurn fork needs Node.js >= 22.13."}'
    fi
    cd "$dir"
    exec node --no-deprecation --import tsx src/cli.ts "${ARGS[@]}"
  fi
  return 1
}

# 1. Explicit executable. Wins over PATH so a fork can be forced when an older codeburn is installed.
if [[ -n "${CODEBURN_BIN:-}" ]]; then
  if [[ -d "$CODEBURN_BIN" ]]; then
    fail '{"error":"CODEBURN_BIN is set but points at a directory, not a codeburn executable."}'
  fi
  if [[ -x "$CODEBURN_BIN" ]]; then
    exec "$CODEBURN_BIN" "${ARGS[@]}"
  fi
  if [[ -f "$CODEBURN_BIN" ]] && command -v node >/dev/null 2>&1; then
    exec node "$CODEBURN_BIN" "${ARGS[@]}"
  fi
  fail '{"error":"CODEBURN_BIN is set but is not a runnable file."}'
fi

# 2. codeburn on PATH (npm link, ~/.local/bin, mise). This is the upstream-compatible default.
if command -v codeburn >/dev/null 2>&1; then
  exec codeburn "${ARGS[@]}"
fi

# 3. Explicit checkout. Must already be in the environment that launches Quickshell.
if [[ -n "${CODEBURN_HOME:-}" ]]; then
  try_checkout "$CODEBURN_HOME" || fail '{"error":"CODEBURN_HOME is set but the checkout has neither dist/cli.js and dist/main.js nor src/cli.ts with node_modules/tsx. Run npm install and npm run build:cli."}'
fi

# 4. Documented default checkout. No session environment variable required.
if [[ -n "${HOME:-}" && -d "$HOME/.local/src/codeburn" ]]; then
  try_checkout "$HOME/.local/src/codeburn" || fail '{"error":"Found ~/.local/src/codeburn but it is not runnable. Run npm install and npm run build:cli there (Node.js >= 22.13)."}'
fi

# 5. Optional npx/bunx spec. Unset by default: a github: spec of this fork does not produce dist/.
#    Example override for the old npm pin: CODEBURN_PACKAGE=codeburn@0.9.27
if [[ -n "${CODEBURN_PACKAGE:-}" ]]; then
  if command -v npx >/dev/null 2>&1; then
    exec npx --yes "$CODEBURN_PACKAGE" "${ARGS[@]}"
  elif command -v bunx >/dev/null 2>&1; then
    exec bunx "$CODEBURN_PACKAGE" "${ARGS[@]}"
  fi
  fail '{"error":"CODEBURN_PACKAGE is set but neither npx nor bunx is on PATH."}'
fi

fail "{\"error\":\"CodeBurn fork not found. Clone https://github.com/GlorifiedTypist/codeburn commit ${CODEBURN_FORK_COMMIT} into ~/.local/src/codeburn, then run npm install and npm run build:cli. A codeburn binary on PATH is used first when present.\"}"
