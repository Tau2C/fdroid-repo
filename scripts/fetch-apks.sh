#!/usr/bin/env bash
set -euo pipefail

APPS_CONFIG="${1:-apps.json}"
DEST_DIR="${2:-repo}"

if [ ! -f "$APPS_CONFIG" ]; then
  echo "Configuration file $APPS_CONFIG does not exist."
  exit 1
fi

mkdir -p "$DEST_DIR"

len=$(jq '. | length' "$APPS_CONFIG")

for (( i=0; i<len; i++ )); do
  repo=$(jq -r ".[$i].repo" "$APPS_CONFIG")
  include_prerelease=$(jq -r ".[$i].include_prerelease" "$APPS_CONFIG")

  # Resolve token: check JSON map REPO_TOKENS, fallback to DEFAULT_GITHUB_TOKEN, fallback to GITHUB_TOKEN
  token=$(REPO_TOKENS="${REPO_TOKENS:-}" jq -nr '
    try (
      (env.REPO_TOKENS | fromjson) as $m |
      $ARGS.named.repo as $r |
      ($m[$r] // empty)
    ) catch empty
  ' --arg repo "$repo" || true)
  token="${token:-${DEFAULT_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}}"

  echo "Fetching releases for $repo (include_prerelease=$include_prerelease)..."

  # Query releases using GitHub CLI or API with resolved token
  releases_json=$(GH_TOKEN="$token" gh release list -R "$repo" --limit 30 --json tagName,isPrerelease,publishedAt)

  echo "$releases_json" | jq -c '.[]' | while read -r item; do
    tag=$(echo "$item" | jq -r '.tagName')
    prerelease=$(echo "$item" | jq -r '.isPrerelease')
    published_at=$(echo "$item" | jq -r '.publishedAt')

    if [ "$prerelease" = "true" ] && [ "$include_prerelease" != "true" ]; then
      continue
    fi

    # Download *.apk files for this release tag
    tmp_dl=$(mktemp -d)
    if GH_TOKEN="$token" gh release download "$tag" -R "$repo" -p "*.apk" -D "$tmp_dl" 2>/dev/null; then
      for apk in "$tmp_dl"/*.apk; do
        if [ -f "$apk" ]; then
          base_name=$(basename "$apk")
          target_file="$DEST_DIR/$base_name"
          if [ ! -f "$target_file" ]; then
            echo "Downloaded $base_name ($tag)"
            mv "$apk" "$target_file"
            touch -d "$published_at" "$target_file"
          else
            echo "File $base_name already exists, skipping."
          fi
        fi
      done
    fi
    rm -rf "$tmp_dl"
  done
done

echo "APK synchronization complete."
