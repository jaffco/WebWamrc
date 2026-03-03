#!/usr/bin/env bash
# serv.sh — Set up and serve the WebWamrc demo.
#
# Uses prebuilt/ by default (committed binaries, no build required).
# Falls back to build/wamrc/ if prebuilt/ is absent.
#
# Usage: ./serv.sh [--build]
#   --build   Run a production webpack build and serve dist/ instead of using
#             the webpack dev server (default: dev server with HMR off).
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
DEMO="$SRC/demo"
PREBUILT="$SRC/prebuilt"
BUILD="$SRC/build/wamrc"

# ---------------------------------------------------------------------------
# Preflight checks — prefer prebuilt/, fall back to build/wamrc/
# ---------------------------------------------------------------------------
if [ -f "$PREBUILT/wamrc.mjs" ]; then
    WAMRC_DIR="$PREBUILT"
elif [ -f "$BUILD/wamrc.mjs" ]; then
    WAMRC_DIR="$BUILD"
    echo "==> Warning: using build/wamrc/ — consider running ./build-wamrc.sh and copying to prebuilt/"
else
    echo "ERROR: No wamrc.mjs found in prebuilt/ or build/wamrc/."
    echo "       Either clone with Git LFS (git lfs pull) or run ./build-wamrc.sh."
    exit 1
fi

# ---------------------------------------------------------------------------
# 1. Link wamrc outputs into demo/ so webpack can find them
# ---------------------------------------------------------------------------
ln -sfn "$WAMRC_DIR" "$DEMO/wamrc"
echo "==> Linked $(basename $WAMRC_DIR) → demo/wamrc"

# ---------------------------------------------------------------------------
# 2. Install JS dependencies if needed
# ---------------------------------------------------------------------------
if [ ! -d "$DEMO/node_modules" ]; then
    echo "==> Installing JS dependencies …"
    npm install --prefix "$DEMO"
fi

# ---------------------------------------------------------------------------
# 3. Serve
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--build" ]]; then
    echo "==> Building production bundle …"
    npm run build --prefix "$DEMO"
    echo ""
    echo "==> Serving demo/dist/ on http://localhost:8080"
    echo "    (COOP/COEP headers required for SharedArrayBuffer — use the dev"
    echo "     server or a server that sets them; python3 -m http.server won't work)"
    cd "$DEMO/dist"
    # npx serve sets custom headers via serve.json if present, but the simplest
    # option that sets COOP/COEP is the webpack dev server pointed at dist/.
    npx --yes webpack serve --config "$DEMO/webpack.config.cjs" --no-hot
else
    echo "==> Starting webpack dev server on http://localhost:8080 …"
    npm run dev --prefix "$DEMO"
fi
