#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash jq curl coreutils
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

  echo "Fetching releases for $repo (include_prerelease=$include_prerelease)..."

  # Query GitHub API for releases
  curl -s -H "Accept: application/vnd.github.v3+json" \
    ${GITHUB_TOKEN:+-H "Authorization: token $GITHUB_TOKEN"} \
    "https://api.github.com/repos/$repo/releases?per_page=30" > /tmp/releases.json

  # Filter releases
  if [ "$include_prerelease" = "true" ]; then
    filter='.'
  else
    filter='map(select(.prerelease == false))'
  fi

  # Extract APK assets
  jq -r "$filter | .[] | .published_at as \$pub | .assets[] | select(.name | endswith(\".apk\")) | \"\(.browser_download_url) \(\$pub) \(.name)\"" /tmp/releases.json | while read -r url published_at name; do
    target_file="$DEST_DIR/$name"
    if [ ! -f "$target_file" ]; then
      echo "Downloading $name from $url..."
      curl -sL -o "$target_file" "$url"
      # Set mtime to match release date
      touch -d "$published_at" "$target_file"
    else
      echo "File $name already exists, skipping."
    fi
  done
done

echo "APK synchronization complete."
