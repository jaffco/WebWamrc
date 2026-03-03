#!/usr/bin/env bash
# build-llvm.sh — Cross-compile LLVM 18 to WebAssembly with Emscripten.
# Produces static LLVM libraries in build/llvm/ for use by wamrc.
#
# Usage: ./build-llvm.sh [build_dir] [llvm_src_dir]
#
# Env vars:
#   LLVM_TARGETS  Semicolon-separated LLVM backends (default: ARM)
#                 e.g. LLVM_TARGETS="ARM" for Cortex-M only (~20-40 min)
#                      LLVM_TARGETS="ARM;AArch64;X86;RISCV;WebAssembly" for all
#   JOBS          Parallel jobs for cmake --build (default: nproc)
#   CCACHE_DIR    Path for ccache cache dir (default: build/ccache)
#                 Set to empty string to disable ccache.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"

BUILD="${1:-$(pwd)/build}"
LLVM_SRC="${2:-$(pwd)/upstream/llvm-project}"

# Only the ARM backend needed for thumbv7em (Cortex-M).  Override via env.
LLVM_TARGETS="${LLVM_TARGETS:-ARM}"

# Parallelism: default to all logical CPUs
JOBS="${JOBS:-0}"
if [ "$JOBS" = "0" ] || [ -z "$JOBS" ]; then
    JOBS=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 4)
fi
echo "==> Using $JOBS parallel jobs"

mkdir -p "$BUILD"
BUILD="$(realpath "$BUILD")"
LLVM_BUILD="$BUILD/llvm"

EMLIB="$SRC/emception/emlib"

# ---------------------------------------------------------------------------
# ccache setup — dramatically speeds up incremental re-builds
# ---------------------------------------------------------------------------
CCACHE_DIR="${CCACHE_DIR:-$BUILD/ccache}"
if command -v ccache &>/dev/null && [ -n "$CCACHE_DIR" ]; then
    export CCACHE_DIR
    mkdir -p "$CCACHE_DIR"
    CCACHE_CMAKE="-DLLVM_CCACHE_BUILD=ON"
    echo "==> ccache enabled (dir: $CCACHE_DIR)"
else
    CCACHE_CMAKE=""
    echo "==> ccache not found, proceeding without it"
fi

# ---------------------------------------------------------------------------
# 1. Clone LLVM 18 if not present
# ---------------------------------------------------------------------------
if [ ! -d "$LLVM_SRC/.git" ]; then
    echo "==> Cloning LLVM release/18.x …"
    git clone --depth 1 --branch release/18.x \
        https://github.com/llvm/llvm-project.git "$LLVM_SRC"
fi

# ---------------------------------------------------------------------------
# 2. Emscripten cross-build of LLVM (static libs only, no tools)
#    LLVM_OPTIMIZED_TABLEGEN automatically builds native tblgen tools in a
#    sub-project, so no separate native configure/build step is needed.
# ---------------------------------------------------------------------------
if [ ! -d "$LLVM_BUILD" ]; then
    echo "==> Configuring LLVM cross-build to WebAssembly …"
    CXXFLAGS="-Dwait4=__syscall_wait4" \
    LDFLAGS="\
        -s LLD_REPORT_UNDEFINED=1 \
        -s ALLOW_MEMORY_GROWTH=1 \
        -s INITIAL_MEMORY=268435456 \
        -s EXPORTED_FUNCTIONS=_main,_free,_malloc \
        -s EXPORTED_RUNTIME_METHODS=FS,PROXYFS,ERRNO_CODES,allocateUTF8 \
        -lproxyfs.js \
        --js-library=$EMLIB/fsroot.js \
    " emcmake cmake -G Ninja \
        -S "$LLVM_SRC/llvm" \
        -B "$LLVM_BUILD" \
        -DCMAKE_BUILD_TYPE=MinSizeRel \
        -DLLVM_TARGETS_TO_BUILD="$LLVM_TARGETS" \
        -DLLVM_ENABLE_PROJECTS="" \
        -DLLVM_ENABLE_DUMP=OFF \
        -DLLVM_ENABLE_ASSERTIONS=OFF \
        -DLLVM_ENABLE_EXPENSIVE_CHECKS=OFF \
        -DLLVM_ENABLE_BACKTRACES=OFF \
        -DLLVM_ENABLE_THREADS=OFF \
        -DLLVM_BUILD_TOOLS=OFF \
        -DLLVM_BUILD_LLVM_DYLIB=OFF \
        -DLLVM_INCLUDE_TESTS=OFF \
        -DLLVM_INCLUDE_UTILS=OFF \
        -DLLVM_INCLUDE_EXAMPLES=OFF \
        -DLLVM_INCLUDE_BENCHMARKS=OFF \
        -DLLVM_ENABLE_TERMINFO=OFF \
        -DLLVM_ENABLE_LIBXML2=OFF \
        -DLLVM_ENABLE_LIBEDIT=OFF \
        -DLLVM_ENABLE_ZLIB=OFF \
        -DLLVM_ENABLE_PIC=OFF \
        -DLLVM_BUILD_STATIC=ON \
        -DCMAKE_SKIP_RPATH=ON \
        -DLLVM_OPTIMIZED_TABLEGEN=ON \
        $CCACHE_CMAKE
fi

echo "==> Building LLVM WebAssembly libraries …"
cmake --build "$LLVM_BUILD" --parallel "$JOBS"

echo "==> LLVM Wasm build complete: $LLVM_BUILD"

if command -v ccache &>/dev/null && [ -n "$CCACHE_DIR" ]; then
    echo "==> ccache stats:"
    ccache --show-stats 2>/dev/null || true
fi
