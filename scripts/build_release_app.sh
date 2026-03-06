#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$PROJECT_DIR/SplitViewBrowser.xcodeproj"
SCHEME="SplitViewBrowser"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PROJECT_DIR/.build/DerivedData}"
OUTPUT_APP_PATH="${OUTPUT_APP_PATH:-$PROJECT_DIR/SplitViewBrowser.app}"
CONFIGURATION="${CONFIGURATION:-Release}"

mkdir -p "$(dirname "$OUTPUT_APP_PATH")"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

BUILT_APP="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/SplitViewBrowser.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "Built app not found: $BUILT_APP" >&2
  exit 1
fi

rm -rf "$OUTPUT_APP_PATH"
cp -R "$BUILT_APP" "$OUTPUT_APP_PATH"

echo "App built: $OUTPUT_APP_PATH"
