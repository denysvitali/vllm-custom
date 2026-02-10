# vLLM AVX2 Docker Builds

Custom vLLM Docker images built for AVX2 CPUs.

## Problem

The official vLLM Docker images require AVX512 instruction set and crash on AVX2-only CPUs with SIGILL errors.

## Solution

This repository hosts GitHub Actions workflows that automatically build vLLM Docker images from source with the `VLLM_CPU_DISABLE_AVX512=true` build argument, making them compatible with AVX2 CPUs.

## Usage

### Pulling Images

Images are published to GitHub Container Registry (GHCR):

```bash
# Pull the latest stable release
docker pull ghcr.io/denysvitali/vllm-custom:latest-avx2

# Pull a specific version
docker pull ghcr.io/denysvitali/vllm-custom:v0.15.1-avx2

# Plain version tag (without -avx2 suffix) also available
docker pull ghcr.io/denysvitali/vllm-custom:v0.15.1
```

### Running

```bash
# Start OpenAI-compatible server
docker run --gpus all -p 8000:8000 ghcr.io/denysvitali/vllm-custom:latest-avx2

# Or without GPU (CPU inference)
docker run -p 8000:8000 ghcr.io/denysvitali/vllm-custom:latest-avx2

# The server will be available at http://localhost:8000
```

### Python Client Example

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8000/v1",
    api_key="token-abc123"
)

response = client.chat.completions.create(
    model="meta-llama/Llama-2-7b-chat-hf",
    messages=[{"role": "user", "content": "Hello!"}],
    max_tokens=100
)
print(response.choices[0].message.content)
```

## Available Tags

- `latest-avx2` - Latest stable release (AVX2 build)
- `vX.Y.Z-avx2` - Version-specific AVX2 tags (e.g., `v0.15.1-avx2`)
- `vX.Y.Z` - Plain version tags (without AVX2 suffix) also available

## Known Limitations

⚠️ **Important:** AVX2 builds do not support tensor parallelism (`-tp=2` or higher). The `-tp` flag will be ignored or may cause errors. Single-CPU inference works fine.

If you need tensor parallelism, you must use AVX512-compatible hardware with the official vLLM images.

## Manual Build Trigger

You can manually trigger a build for a specific vLLM version:

1. Go to the repository's **Actions** tab on GitHub
2. Select **Build vLLM AVX2 Docker Image** from the left sidebar
3. Click **Run workflow**
4. Enter the vLLM version/tag (e.g., `v0.15.1`) - leave empty for latest
5. Click **Run workflow**

## Automated Builds

- **Daily check**: Workflow runs daily at 2 AM UTC to check for new releases
- **On main branch updates**: When workflow files or README change
- **On manual trigger**: As described above

## Setup Instructions

### Prerequisites

1. A GitHub repository (fork this one or create your own)
2. GitHub Actions enabled
3. GitHub Container Registry (GHCR) enabled

### Configuration

1. Fork this repository to your GitHub account

2. Enable GitHub Actions if not already enabled

3. Create a Personal Access Token (PAT):
   - Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
   - Generate new token with `packages:write` scope
   - Copy the token

4. Add the token as a repository secret:
   - Go to your repository → Settings → Secrets and variables → Actions
   - Click **New repository secret**
   - Name: `REGISTRY_TOKEN`
   - Value: paste your PAT
   - Click **Add secret**

   Note: You can also use the default `GITHUB_TOKEN` which has packages:write permissions by default, but a PAT gives you more control.

5. Update the workflow files if you want to target a different registry:
   - Replace `ghcr.io` with your registry of choice
   - Adjust authentication accordingly

6. Push the code to your GitHub repository (main/master branch)

7. Workflows will run automatically (daily or on manual trigger)

### Making Images Public

By default, images in GHCR are private. To make them public:

1. Go to your repository's Packages page: `https://github.com/orgs/YOUR_ORG/packages?repo_name=YOUR_REPO`
2. Find the `vllm-custom` package
3. Click on it, then go to **Package settings**
4. Under **Visibility**, select **Public**
5. Click **Save**

## Customization

### Different Registry

To use Docker Hub or another registry:

1. Edit `.github/workflows/build-avx2.yml`
2. Replace `ghcr.io` with your registry (e.g., `docker.io/username`)
3. Update the `docker login` step with appropriate credentials
4. Add registry-specific secrets for authentication

### Different Tag Naming

Modify the `tags:` section in the build step to customize tag format.

### Retain More/Fewer Versions

Edit `.github/workflows/cleanup.yml` and change the `KEEP_VERSIONS` variable in the Python script (default: 10).

## Local Testing

You can test the build locally before pushing:

```bash
# Clone vLLM source at a specific version
git clone --depth 1 --branch v0.15.1 https://github.com/vllm-project/vllm.git
cd vllm

# Build the image
docker build -f docker/Dockerfile.cpu \
  --build-arg VLLM_CPU_DISABLE_AVX512="true" \
  --tag vllm-custom:test \
  --target vllm-openai .

# Run it
docker run -p 8000:8000 vllm-custom:test
```

## Troubleshooting

### Build fails with authentication errors

Make sure the `REGISTRY_TOKEN` or `GITHUB_TOKEN` secret is correctly configured and has the necessary permissions.

### Rate limit when fetching latest release

The workflow includes a fallback to a hardcoded version if GitHub API rate limits are hit. You can also specify the version manually via workflow dispatch.

### Container crashes on startup

Check that your hardware supports AVX2 (most CPUs from 2011+ do). Run `grep avx2 /proc/cpuinfo` to verify.

### Pull permission denied

Make sure the package is public (see "Making Images Public" above) or authenticate:
  ```bash
  docker login ghcr.io
  # Use your GitHub username and PAT as password
  ```

## How It Works

1. The workflow runs on a schedule or manual trigger
2. It determines which vLLM version to build (from input or GitHub API)
3. It uses Docker Buildx to build directly from the vLLM repository without cloning
4. The build uses `docker/Dockerfile.cpu` from vLLM with `VLLM_CPU_DISABLE_AVX512=true`
5. The image is tagged with version and pushed to GHCR
6. The `latest-avx2` tag is also updated if building the latest release

## Credits

- vLLM: https://github.com/vllm-project/vllm
- Based on the official vLLM Docker setup

## License

This repository (workflows and scripts) is licensed under the MIT License.
The vLLM image is subject to vLLM's license (Apache 2.0).
