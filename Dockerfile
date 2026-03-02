# syntax=docker/dockerfile:1
# ^^^ Required for BuildKit cache mount syntax.
# Build with:  docker build -t webwamrc-builder .
# Or faster:   DOCKER_BUILDKIT=1 docker build --build-arg JOBS=$(nproc) -t webwamrc-builder .

FROM emscripten/emsdk:3.1.24 AS base

ARG JOBS=0
# 0 means "let the script auto-detect via nproc"
ENV JOBS=${JOBS}

RUN DEBIAN_FRONTEND=noninteractive apt --no-install-recommends -qy update && \
    DEBIAN_FRONTEND=noninteractive apt --no-install-recommends -qy install \
    pkg-config ninja-build python3 python3-pip brotli git ccache && \
    pip3 install --quiet cmake==3.27.9

# Verify cmake version satisfies LLVM 18's cmake_minimum_required(3.20)
RUN cmake --version | head -1

ENV PATH="${EMSDK}/upstream/bin:${PATH}"
# Point ccache at a BuildKit cache volume so it survives across docker builds
ENV CCACHE_DIR=/cache/ccache

WORKDIR /webwamrc

COPY build-llvm.sh build-wamrc.sh ./
COPY wasm-micro-runtime/ wasm-micro-runtime/
COPY emception/emlib/ emception/emlib/

RUN chmod +x build-llvm.sh build-wamrc.sh

# ---------------------------------------------------------------------------
# Stage: llvm
# Build LLVM static libs.  This layer is cached independently from wamrc, so
# tweaking JS/wamrc code never invalidates the multi-hour LLVM build.
# The --mount=type=cache persists ccache AND the git clone across rebuilds.
# ---------------------------------------------------------------------------
FROM base AS llvm

RUN --mount=type=cache,target=/cache/ccache \
    --mount=type=cache,target=/webwamrc/upstream \
    ./build-llvm.sh

# ---------------------------------------------------------------------------
# Stage: wamrc
# Build wamrc on top of the LLVM artifacts from the previous stage.
# Re-runs in seconds if only wamrc source changed.
# ---------------------------------------------------------------------------
FROM llvm AS wamrc-build

RUN --mount=type=cache,target=/cache/ccache \
    ./build-wamrc.sh

# ---------------------------------------------------------------------------
# Final stage: export only the artifacts (small image)
# ---------------------------------------------------------------------------
FROM scratch AS artifacts

COPY --from=wamrc-build /webwamrc/build/wamrc/wamrc.mjs  /
COPY --from=wamrc-build /webwamrc/build/wamrc/wamrc.wasm /

# To extract artifacts after build:
#   docker build --target wamrc-build -t webwamrc-builder .
#   CID=$(docker create webwamrc-builder)
#   docker cp $CID:/webwamrc/build/wamrc/wamrc.mjs  demo/wamrc/
#   docker cp $CID:/webwamrc/build/wamrc/wamrc.wasm demo/wamrc/
#   docker rm $CID
