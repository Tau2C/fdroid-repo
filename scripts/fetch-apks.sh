#!/usr/bin/env bash
set -euo pipefail

APPS_CONFIG="${1:-apps.json}"
DEST_DIR="${2:-repo}"
META_DIR="${3:-metadata}"

if [ ! -f "$APPS_CONFIG" ]; then
  echo "Configuration file $APPS_CONFIG does not exist."
  exit 1
fi

mkdir -p "$DEST_DIR" "$META_DIR"

len=$(jq '. | length' "$APPS_CONFIG")

for (( i=0; i<len; i++ )); do
  repo=$(jq -r ".[$i].repo" "$APPS_CONFIG")
  package_id=$(jq -r ".[$i].package_id // empty" "$APPS_CONFIG")
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

  # Query releases using GitHub CLI with resolved token
  releases_json=$(GH_TOKEN="$token" gh release list -R "$repo" --limit 30 --json tagName,isPrerelease,publishedAt)

  # Find latest stable (non-prerelease) release tag
  latest_stable_tag=$(echo "$releases_json" | jq -r 'map(select(.isPrerelease == false)) | .[0].tagName // empty')

  # Download APKs
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

  # Auto-generate metadata if package_id and stable tag exist
  if [ -n "$package_id" ] && [ -n "$latest_stable_tag" ]; then
    clean_version="${latest_stable_tag#v}"
    meta_file="$META_DIR/$package_id.yml"

    # Search for an APK in DEST_DIR matching the stable tag
    stable_apk=$(find "$DEST_DIR" -maxdepth 1 -name "*${clean_version}*.apk" -o -name "*${latest_stable_tag}*.apk" | head -n 1 || true)

    version_code=""
    if [ -n "$stable_apk" ] && [ -f "$stable_apk" ]; then
      # Extract versionCode using python3 + androguard (installed with fdroidserver)
      version_code=$(python3 -c "
try:
    from androguard.core.bytecodes.apk import APK
    apk = APK('$stable_apk')
    print(apk.get_androidversion_code() or '')
except Exception:
    pass
" 2>/dev/null || true)
    fi

    echo "Updating metadata for $package_id: CurrentVersion=$clean_version, CurrentVersionCode=${version_code:-none} (from stable tag $latest_stable_tag)..."
    if [ -f "$meta_file" ]; then
      # Update or append CurrentVersion in existing metadata file
      if grep -q "^CurrentVersion:" "$meta_file"; then
        sed -i "s/^CurrentVersion:.*/CurrentVersion: $clean_version/" "$meta_file"
      else
        echo "CurrentVersion: $clean_version" >> "$meta_file"
      fi

      # Update or append CurrentVersionCode if detected
      if [ -n "$version_code" ]; then
        if grep -q "^CurrentVersionCode:" "$meta_file"; then
          sed -i "s/^CurrentVersionCode:.*/CurrentVersionCode: $version_code/" "$meta_file"
        else
          echo "CurrentVersionCode: $version_code" >> "$meta_file"
        fi
      fi
    else
      cat << EOF > "$meta_file"
AutoUpdateMode: None
UpdateCheckMode: None
CurrentVersion: $clean_version
${version_code:+CurrentVersionCode: $version_code}
EOF
    fi
  fi
done

echo "APK and metadata synchronization complete."
