#!/usr/bin/env bash
# Local build script for testing vLLM AVX2 images
# Usage: ./scripts/build.sh [version]

set -e

VERSION="${1:-v0.15.1}"

echo "Building vLLM AVX2 Docker image for version: $VERSION"
echo ""

# Clone vLLM repository at specified version
if [ -d "vllm" ]; then
    echo "Removing existing vllm directory..."
    rm -rf vllm
fi

echo "Cloning vLLM repository..."
git clone --depth 1 --branch "$VERSION" https://github.com/vllm-project/vllm.git
cd vllm

# Build the image
echo "Building Docker image..."
docker build -f docker/Dockerfile.cpu \
  --build-arg VLLM_CPU_DISABLE_AVX512="true" \
  --tag vllm-avx2:"$VERSION" \
  --target vllm-openai .

echo ""
echo "Build complete!"
echo "Image tag: vllm-avx2:$VERSION"
echo ""
echo "To run:"
echo "  docker run --gpus all -p 8000:8000 vllm-avx2:$VERSION"
echo ""
echo "To test:"
echo "  docker run --rm vllm-avx2:$VERSION --help"
