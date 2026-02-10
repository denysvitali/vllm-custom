#!/usr/bin/env python3
"""
Clean up old vLLM Docker images from GHCR.
Keeps the N most recent versions plus the 'latest' tag.
"""

import os
import sys
import requests
from packaging import version as pkg_version

# Configuration
REGISTRY = "ghcr.io"
PACKAGE_NAME = "vllm-custom"
KEEP_VERSIONS = 10  # Number of version tags to keep (besides 'latest')

# GitHub API endpoints
API_BASE = "https://api.github.com"
# Get repository info from GITHUB_REPOSITORY env var or construct from owner/repo
REPOSITORY = os.getenv("GITHUB_REPOSITORY", "").split("/")[-1]
OWNER = os.getenv("GITHUB_REPOSITORY_OWNER", "") or os.getenv("GITHUB_ACTOR", "")


def get_tags():
    """Fetch all tags for the package from GHCR."""
    if not OWNER or not REPOSITORY:
        print("Error: Could not determine repository owner/name.")
        print("Set GITHUB_REPOSITORY or GITHUB_REPOSITORY_OWNER environment variables.")
        sys.exit(1)

    url = f"{API_BASE}/orgs/{OWNER}/packages/container/{PACKAGE_NAME}/versions"
    headers = {
        "Authorization": f"Bearer {os.getenv('GITHUB_TOKEN')}",
        "Accept": "application/vnd.github+json"
    }

    all_tags = []
    page = 1
    per_page = 100

    while True:
        response = requests.get(
            url,
            headers=headers,
            params={"per_page": per_page, "page": page}
        )

        if response.status_code != 200:
            print(f"Error fetching package versions: {response.status_code}")
            print(response.text)
            sys.exit(1)

        data = response.json()
        if not data:
            break

        for pkg_version in data:
            metadata = pkg_version.get("metadata", {}).get("container", {}).get("tags", [])
            all_tags.append({
                "id": pkg_version["id"],
                "tags": metadata,
                "created_at": pkg_version["created_at"]
            })

        if len(data) < per_page:
            break
        page += 1

    return all_tags


def parse_version(tag):
    """Parse version from tag, returning a comparable version object or None."""
    # Skip 'latest' and non-version tags
    if tag == "latest":
        return None

    # Remove common suffixes like '-avx2'
    cleaned = tag.replace("-avx2", "")

    # Try to parse as version
    try:
        return pkg_version.parse(cleaned)
    except pkg_version.InvalidVersion:
        return None


def should_preserve_tag(tag, preserved_versions):
    """Determine if a tag should be preserved."""
    if tag in ("latest", "latest-avx2"):
        return True

    parsed = parse_version(tag)
    if not parsed:
        return True  # Preserve non-semantic version tags

    # Check if this version is in our preserved set
    return parsed in preserved_versions


def main():
    print(f"Fetching package versions for {OWNER}/{PACKAGE_NAME}...")
    versions = get_tags()
    print(f"Found {len(versions)} image versions")

    # Collect all tags and sort by version
    version_tags = []
    for v in versions:
        for tag in v["tags"]:
            parsed = parse_version(tag)
            if parsed:
                version_tags.append({
                    "tag": tag,
                    "version": parsed,
                    "id": v["id"],
                    "created_at": v["created_at"]
                })

    # Sort by version (descending)
    version_tags.sort(key=lambda x: x["version"], reverse=True)

    # Keep N most recent versions plus 'latest'
    to_keep_versions = set(v["version"] for v in version_tags[:KEEP_VERSIONS])
    print(f"Keeping {KEEP_VERSIONS} most recent versions:")
    for v in version_tags[:KEEP_VERSIONS]:
        print(f"  - {v['tag']}")

    # Now find which versions to delete (by package ID)
    to_delete_ids = set()
    preserved_tags = []

    for v in versions:
        keep_this = False
        for tag in v["tags"]:
            if should_preserve_tag(tag, to_keep_versions):
                preserved_tags.append(tag)
                keep_this = True
                break
        if not keep_this:
            to_delete_ids.add(v["id"])

    print(f"\nTotal tags: {sum(len(v['tags']) for v in versions)}")
    print(f"Preserved tags: {len(preserved_tags)}")
    print(f"Image versions to delete: {len(to_delete_ids)}")

    if not to_delete_ids:
        print("No images to delete.")
        return

    # Confirm deletion (if running interactively, else skip)
    if os.getenv("CI"):
        print("Running in CI mode, proceeding with deletion...")
    else:
        response = input(f"\nDelete {len(to_delete_ids)} old images? (y/N): ")
        if response.lower() != 'y':
            print("Aborted.")
            return

    # Delete images
    url = f"{API_BASE}/orgs/{OWNER}/packages/container/{PACKAGE_NAME}/versions"
    headers = {
        "Authorization": f"Bearer {os.getenv('GITHUB_TOKEN')}",
        "Accept": "application/vnd.github+json"
    }

    deleted = 0
    for version_id in to_delete_ids:
        response = requests.delete(f"{url}/{version_id}", headers=headers)
        if response.status_code == 204:
            print(f"✓ Deleted image version {version_id}")
            deleted += 1
        else:
            print(f"✗ Failed to delete {version_id}: {response.status_code}")
            print(response.text)

    print(f"\nDeleted {deleted}/{len(to_delete_ids)} images.")


if __name__ == "__main__":
    main()
