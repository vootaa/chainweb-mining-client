# syntax=docker/dockerfile:1

# Vootaa chainweb-mining-client image.
# Builds the mining client binary from source using GHC/cabal.
#
# Build:
#   docker buildx build --target=chainweb-mining-client -t vootaa/chainweb-mining-client:local .
#
# Skip tests:
#   docker buildx build --target=chainweb-mining-client-bin -t vootaa/chainweb-mining-client:local .

ARG UBUNTU_VERSION=22.04
ARG GHC_VERSION=9.10.1
ARG PROJECT_NAME=chainweb-mining-client

# ############################################################################ #
# Runtime base
# ############################################################################ #

FROM ubuntu:${UBUNTU_VERSION} AS mining-client-runtime
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y \
    && apt-get install -yqq --no-install-recommends \
        ca-certificates \
        libffi8 \
        libgmp10 \
        libncurses6 \
        libssl3 \
        zlib1g \
    && rm -rf /var/lib/apt/lists/*

# ############################################################################ #
# Build base: GHC + cabal via ghcup
# ############################################################################ #

FROM ubuntu:${UBUNTU_VERSION} AS mining-client-build
ARG GHC_VERSION
ARG TARGETPLATFORM
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y \
    && apt-get install -yqq --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        libffi-dev \
        libgmp-dev \
        libncurses-dev \
        libssl-dev \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Install GHC and cabal via ghcup (non-interactive)
ENV BOOTSTRAP_HASKELL_NONINTERACTIVE=1
ENV BOOTSTRAP_HASKELL_MINIMAL=1
RUN curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | \
    BOOTSTRAP_HASKELL_GHC_VERSION=${GHC_VERSION} \
    BOOTSTRAP_HASKELL_CABAL_VERSION=recommended \
    sh

ENV PATH="/root/.ghcup/bin:/root/.cabal/bin:$PATH"

WORKDIR /chainweb-mining-client

# Pre-fetch dependency metadata
RUN --mount=type=cache,target=/root/.cabal \
    cabal update

# Copy source and build
COPY . .

RUN --mount=type=cache,target=/root/.cabal,id=${PROJECT_NAME}-${TARGETPLATFORM},sharing=locked \
    --mount=type=cache,target=./dist-newstyle,id=${PROJECT_NAME}-dist-${TARGETPLATFORM},sharing=locked \
    cabal build chainweb-mining-client:exe:chainweb-mining-client

RUN --mount=type=cache,target=/root/.cabal,id=${PROJECT_NAME}-${TARGETPLATFORM},sharing=locked \
    --mount=type=cache,target=./dist-newstyle,id=${PROJECT_NAME}-dist-${TARGETPLATFORM},sharing=locked \
    mkdir -p artifacts && \
    cp $(cabal list-bin chainweb-mining-client:exe:chainweb-mining-client) artifacts/chainweb-mining-client

# ############################################################################ #
# Final image: binary only
# ############################################################################ #

FROM mining-client-runtime AS chainweb-mining-client-bin
WORKDIR /chainweb-mining-client
COPY --from=mining-client-build /chainweb-mining-client/artifacts/chainweb-mining-client .
RUN chmod 755 chainweb-mining-client
ENV PATH="/chainweb-mining-client:$PATH"
ENTRYPOINT ["/chainweb-mining-client/chainweb-mining-client"]

# ############################################################################ #
# Tested image (runs test suite before finalizing)
# ############################################################################ #

FROM mining-client-build AS mining-client-test
ARG TARGETPLATFORM
ARG PROJECT_NAME
RUN --mount=type=cache,target=/root/.cabal,id=${PROJECT_NAME}-${TARGETPLATFORM},sharing=locked \
    --mount=type=cache,target=./dist-newstyle,id=${PROJECT_NAME}-dist-${TARGETPLATFORM},sharing=locked \
    cabal test chainweb-mining-client:test:tests

FROM chainweb-mining-client-bin AS chainweb-mining-client
COPY --from=mining-client-test /etc/hostname /tmp/tests-passed
RUN rm -f /tmp/tests-passed
