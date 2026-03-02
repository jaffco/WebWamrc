#!/usr/bin/env bash
# build-wamrc.sh — Cross-compile wamrc to WebAssembly with Emscripten.
# Requires build/llvm/ to already be built (run build-llvm.sh first).
#
# Usage: ./build-wamrc.sh [build_dir]
#
# Env vars:
#   JOBS       Parallel jobs (default: nproc)
#   CCACHE_DIR Path for ccache dir (default: build/ccache, same as build-llvm.sh)
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"

BUILD="${1:-$(pwd)/build}"
BUILD="$(realpath "$BUILD")"

JOBS="${JOBS:-0}"
if [ "$JOBS" = "0" ] || [ -z "$JOBS" ]; then
    JOBS=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 4)
fi
echo "==> Using $JOBS parallel jobs"

LLVM_BUILD="$BUILD/llvm"
WAMRC_BUILD="$BUILD/wamrc"
WAMR_SRC="$SRC/wasm-micro-runtime"
EMLIB="$SRC/emception/emlib"

# ccache — reuse the same cache dir as build-llvm.sh
CCACHE_DIR="${CCACHE_DIR:-$BUILD/ccache}"
if command -v ccache &>/dev/null && [ -n "$CCACHE_DIR" ]; then
    export CCACHE_DIR
    mkdir -p "$CCACHE_DIR"
    CCACHE_CMAKE="-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
    echo "==> ccache enabled (dir: $CCACHE_DIR)"
else
    CCACHE_CMAKE=""
fi

if [ ! -d "$LLVM_BUILD/lib/cmake/llvm" ]; then
    echo "ERROR: LLVM CMake config not found at $LLVM_BUILD/lib/cmake/llvm"
    echo "       Run ./build-llvm.sh first."
    exit 1
fi

if [ ! -d "$WAMRC_BUILD" ]; then
    echo "==> Configuring wamrc cross-build to WebAssembly …"
    CFLAGS="-DBH_HAS_DLFCN=0" \
    CXXFLAGS="-DBH_HAS_DLFCN=0" \
    LDFLAGS="\
        -s ALLOW_MEMORY_GROWTH=1 \
        -s INITIAL_MEMORY=268435456 \
        -s MAXIMUM_MEMORY=4294967296 \
        -s EXPORTED_FUNCTIONS=_main,_free,_malloc \
        -s EXPORTED_RUNTIME_METHODS=FS,PROXYFS,ERRNO_CODES,allocateUTF8 \
        -s MODULARIZE=1 \
        -s EXPORT_ES6=1 \
        -s USE_ES6_IMPORT_META=0 \
        -s ENVIRONMENT=worker \
        -s NODEJS_CATCH_EXIT=0 \
        -lproxyfs.js \
        --js-library=$EMLIB/fsroot.js \
    " emcmake cmake -G Ninja \
        -S "$WAMR_SRC/wamr-compiler" \
        -B "$WAMRC_BUILD" \
        -DCMAKE_BUILD_TYPE=MinSizeRel \
        -DWAMR_BUILD_PLATFORM=linux \
        -DWAMR_BUILD_TARGET=X86_64 \
        -DWAMR_BUILD_DEBUG_AOT=0 \
        -DWAMR_BUILD_LIBC_WASI=1 \
        -DWAMR_BUILD_WITH_CUSTOM_LLVM=1 \
        -DLLVM_DIR="$LLVM_BUILD/lib/cmake/llvm" \
        $CCACHE_CMAKE
fi

echo "==> Building wamrc …"
cmake --build "$WAMRC_BUILD" --parallel "$JOBS" -- wamrc

# Rename output to .mjs so it can be imported as an ES module
WAMRC_JS="$WAMRC_BUILD/wamrc.js"
WAMRC_MJS="$WAMRC_BUILD/wamrc.mjs"
if [ -f "$WAMRC_JS" ] && [ ! -f "$WAMRC_MJS" ]; then
    mv "$WAMRC_JS" "$WAMRC_MJS"
fi

echo "==> wamrc Wasm build complete."
echo "    JS glue:  $WAMRC_BUILD/wamrc.mjs"
echo "    Wasm:     $WAMRC_BUILD/wamrc.wasm"

# Optional: compress with brotli for efficient serving
if command -v brotli &>/dev/null; then
    echo "==> Compressing wamrc.wasm with brotli …"
    brotli --best --force "$WAMRC_BUILD/wamrc.wasm"
    echo "    Compressed: $WAMRC_BUILD/wamrc.wasm.br"
fi
