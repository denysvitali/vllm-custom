#!/usr/bin/env bash
# Fetch and display the latest vLLM release version

set -e

echo "Fetching latest vLLM release from GitHub..."

response=$(curl -s https://api.github.com/repos/vllm-project/vllm/releases/latest)

# Check for rate limiting
if echo "$response" | grep -q 'API rate limit exceeded'; then
    echo "Warning: GitHub API rate limit exceeded."
    echo "Using fallback version: v0.15.1"
    echo "v0.15.1"
    exit 0
fi

# Extract tag_name using jq
if command -v jq &> /dev/null; then
    tag=$(echo "$response" | jq -r '.tag_name')
    if [ "$tag" != "null" ] && [ -n "$tag" ]; then
        echo "Latest version: $tag"
        echo "$tag"
    else
        echo "Error: Could not parse version from response"
        echo "Response: $response"
        exit 1
    fi
else
    # Fallback to grep/sed if jq not available
    tag=$(echo "$response" | grep -o '"tag_name":[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    if [ -n "$tag" ]; then
        echo "Latest version: $tag"
        echo "$tag"
    else
        echo "Error: jq is not installed and fallback parsing failed"
        exit 1
    fi
fi
