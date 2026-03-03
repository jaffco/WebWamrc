#!/usr/bin/env bash
# build.sh — Full WebWamrc build orchestrator.
# Runs inside Docker (emscripten/emsdk:3.1.24) or a local Emscripten environment.
#
# Steps:
#   1. build-llvm.sh  — clone + native-tblgen + wasm LLVM libs
#   2. build-wamrc.sh — wasm wamrc binary
#   3. npm install + webpack — JS/HTML demo bundle
#
# Usage:
#   ./build.sh                     # build everything
#   ./build.sh --docker            # build via Docker (auto-pulls image)
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
BUILD="${BUILD:-$SRC/build}"

if [[ "${1:-}" == "--docker" ]]; then
    echo "==> Building via Docker …"
    docker build -t webwamrc-builder -f "$SRC/Dockerfile" "$SRC"
    # Copy artifacts out
    mkdir -p "$BUILD/wamrc"
    CID=$(docker create webwamrc-builder)
    docker cp "$CID:/webwamrc/build/wamrc/wamrc.mjs" "$BUILD/wamrc/"
    docker cp "$CID:/webwamrc/build/wamrc/wamrc.wasm" "$BUILD/wamrc/"
    if docker cp "$CID:/webwamrc/build/wamrc/wamrc.wasm.br" "$BUILD/wamrc/" 2>/dev/null; then
        echo "    Copied brotli-compressed wasm"
    fi
    docker rm "$CID"
    echo "==> Docker build complete. Artifacts in $BUILD/wamrc/"
else
    echo "==> Step 1/3: Build LLVM"
    "$SRC/build-llvm.sh" "$BUILD"

    echo "==> Step 2/3: Build wamrc"
    "$SRC/build-wamrc.sh" "$BUILD"

    # Copy distributable artifacts to prebuilt/ and update symlinks
    echo "==> Updating prebuilt/ …"
    mkdir -p "$SRC/prebuilt"
    cp "$BUILD/wamrc/wamrc.js-2.4.3"    "$SRC/prebuilt/"
    cp "$BUILD/wamrc/wamrc.js-2.4.wasm" "$SRC/prebuilt/"
    cp "$BUILD/wamrc/wamrc.wasm.br"     "$SRC/prebuilt/"
    ln -sf wamrc.js-2.4.3    "$SRC/prebuilt/wamrc.mjs"
    ln -sf wamrc.js-2.4.wasm "$SRC/prebuilt/wamrc.wasm"
    echo "    Artifacts copied to prebuilt/"

    # Link prebuilt/ into demo/ so webpack can find them
    ln -sfn "$SRC/prebuilt" "$SRC/demo/wamrc"

    echo "==> Step 3/3: Build JS demo"
    cd "$SRC/demo"
    npm install
    npm run build

    echo ""
    echo "==> All done! Serve the demo/dist/ directory:"
    echo "    cd demo/dist && python3 -m http.server 8080"
fi
