# This Dockerfile wraps vLLM's Dockerfile.cpu to add version override support
# for building from shallow git clones where setuptools-scm can't detect version

ARG VLLM_VERSION
ARG VLLM_CPU_DISABLE_AVX512=true

# Build stage that adds version override support
FROM ubuntu:22.04 AS version-patch

# We'll use this to patch the source before building

# Import the vLLM build stage and override the build step
# Note: We need to clone vLLM source separately and pass it as context

# Start from scratch and define our own build
FROM ubuntu:22.04 AS base-common

WORKDIR /workspace

ARG PYTHON_VERSION=3.12
ARG PIP_EXTRA_INDEX_URL="https://download.pytorch.org/whl/cpu"
ARG VLLM_VERSION

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -y \
    && apt-get install -y --no-install-recommends sudo ccache git curl wget ca-certificates \
    gcc-12 g++-12 libtcmalloc-minimal4 libnuma-dev ffmpeg libsm6 libxext6 libgl1 jq lsof \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 10 --slave /usr/bin/g++ g++ /usr/bin/g++-12 \
    && curl -LsSf https://astral.sh/uv/install.sh | sh

ENV CC=/usr/bin/gcc-12 CXX=/usr/bin/g++-12
ENV CCACHE_DIR=/root/.cache/ccache
ENV CMAKE_CXX_COMPILER_LAUNCHER=ccache

ENV PATH="/root/.local/bin:$PATH"
ENV VIRTUAL_ENV="/opt/venv"
ENV UV_PYTHON_INSTALL_DIR=/opt/uv/python
RUN uv venv --python ${PYTHON_VERSION} --seed ${VIRTUAL_ENV}
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

ENV UV_HTTP_TIMEOUT=500

ENV PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL}
ENV UV_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL}
ENV UV_INDEX_STRATEGY="unsafe-best-match"
ENV UV_LINK_MODE="copy"

COPY requirements/common.txt requirements/common.txt
COPY requirements/cpu.txt requirements/cpu.txt

RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --upgrade pip && \
    uv pip install -r requirements/cpu.txt

ARG TARGETARCH
ENV TARGETARCH=${TARGETARCH}

FROM base-common AS base-amd64
ENV LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so.4:/opt/venv/lib/libiomp5.so"

FROM base-common AS base-arm64
ENV LD_PRELOAD="/usr/lib/aarch64-linux-gnu/libtcmalloc_minimal.so.4"

FROM base-${TARGETARCH} AS base
RUN echo 'ulimit -c 0' >> ~/.bashrc

FROM base AS vllm-build

ARG max_jobs=32
ENV MAX_JOBS=${max_jobs}

ARG GIT_REPO_CHECK=0
ARG VLLM_CPU_DISABLE_AVX512=0
ENV VLLM_CPU_DISABLE_AVX512=${VLLM_CPU_DISABLE_AVX512}
ARG VLLM_CPU_AVX2=0
ENV VLLM_CPU_AVX2=${VLLM_CPU_AVX2}
ARG VLLM_CPU_AVX512=0
ENV VLLM_CPU_AVX512=${VLLM_CPU_AVX512}
ARG VLLM_CPU_AVX512BF16=0
ENV VLLM_CPU_AVX512BF16=${VLLM_CPU_AVX512BF16}
ARG VLLM_CPU_AVX512VNNI=0
ENV VLLM_CPU_AVX512VNNI=${VLLM_CPU_AVX512VNNI}
ARG VLLM_CPU_AMXBF16=0
ENV VLLM_CPU_AMXBF16=${VLLM_CPU_AMXBF16}

# Version override support for shallow clones
ARG VLLM_VERSION
ENV VLLM_VERSION_OVERRIDE=${VLLM_VERSION}

COPY requirements/cpu-build.txt requirements/build.txt
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install -r requirements/build.txt

COPY . .

RUN if [ "${GIT_REPO_CHECK}" != 0 ]; then bash tools/check_repo.sh ; fi

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=cache,target=/root/.cache/ccache \
    --mount=type=cache,target=/workspace/vllm/.deps,sharing=locked \
    VLLM_TARGET_DEVICE=cpu python3 setup.py bdist_wheel --dist-dir=dist --py-limited-api=cp38

FROM base AS vllm-openai

COPY --from=vllm-build /workspace/dist /workspace/dist

RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install /workspace/dist/*.whl

COPY examples/ /workspace/examples/
COPY benchmarks/ /workspace/benchmarks/

ENV VLLM_USAGE_SOURCE=production-docker-image

ENTRYPOINT ["python3", "-m", "vllm.entrypoints.openai.api_server"]
