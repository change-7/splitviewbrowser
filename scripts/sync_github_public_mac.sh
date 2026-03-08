#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="${1:-$ROOT_DIR/GitHub_Public_Mac}"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/splitviewbrowser-public-sync.XXXXXX")"

cleanup() {
  rm -rf "$STAGE_DIR"
}

trap cleanup EXIT

INCLUDE_ITEMS=(
  "SplitViewBrowser"
  "SplitViewBrowser.xcodeproj"
  "SplitViewBrowserTests"
  "scripts"
  "README.md"
  "project.yml"
  "SplitViewBrowser-Installer.dmg"
)

echo "[sync] Source: $ROOT_DIR"
echo "[sync] Target: $DEST_DIR"

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

for item in "${INCLUDE_ITEMS[@]}"; do
  src_path="$ROOT_DIR/$item"
  dst_path="$STAGE_DIR/$item"
  if [[ -e "$src_path" ]]; then
    mkdir -p "$(dirname "$dst_path")"
    cp -R "$src_path" "$dst_path"
  fi
done

# 공개 제외 대상 정리
rm -rf \
  "$STAGE_DIR/AGENTS.md" \
  "$STAGE_DIR/SESSION_HANDOFF.md" \
  "$STAGE_DIR/mobile" \
  "$STAGE_DIR/build" \
  "$STAGE_DIR/SplitViewBrowser.app" \
  "$STAGE_DIR/SplitViewBrowser_GitHub_Copy" \
  "$STAGE_DIR/VERSION_HISTORY.md"

# 내부 산출물/개인 파일 제거
find "$STAGE_DIR" -name ".DS_Store" -delete
find "$STAGE_DIR" -name "xcuserdata" -type d -prune -exec rm -rf {} +
find "$STAGE_DIR" -name "*.xcuserstate" -delete
find "$STAGE_DIR" -name "*.app" -type d -prune -exec rm -rf {} +
find "$STAGE_DIR" -name "build" -type d -prune -exec rm -rf {} +

# 공개용 .gitignore 생성
cat > "$STAGE_DIR/.gitignore" <<'EOF'
# macOS
.DS_Store

# Xcode user data
*.xcuserdatad
*.xcuserstate
*.xccheckout
*.moved-aside
*.pbxuser
xcuserdata/

# Build outputs
build/
DerivedData/
*.app/

# Swift Package Manager
.build/

# Internal / private folders
AGENTS.md
SESSION_HANDOFF.md
mobile/
SplitViewBrowser_GitHub_Copy/
VERSION_HISTORY.md
GitHub_Public_Mac/
EOF

if [[ -d "$DEST_DIR/.git" ]]; then
  find "$DEST_DIR" -mindepth 1 -maxdepth 1 ! -name ".git" -exec rm -rf {} +
else
  rm -rf "$DEST_DIR"
  mkdir -p "$DEST_DIR"
fi

cp -R "$STAGE_DIR"/. "$DEST_DIR"/

# 민감 경로 노출 검증(경고)
if command -v rg >/dev/null 2>&1; then
  if rg -n --hidden -S '/Users/[^/]+|/home/[^/]+' "$DEST_DIR" \
    --glob '!**/sync_github_public_mac.sh' >/tmp/public_scan_result.txt 2>/dev/null; then
    echo "[warn] Potential local path leakage detected:"
    sed -n '1,120p' /tmp/public_scan_result.txt
  else
    echo "[ok] No local user path patterns found in public folder."
  fi
fi

echo "[done] GitHub public folder refreshed: $DEST_DIR"
