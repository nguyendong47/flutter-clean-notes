#!/usr/bin/env bash
set -euo pipefail

REQUIRED_GROUP="group.com.cleannotes.app"
EXPECTED_TITLE="AppGroupSyncTest Title 98765"

UDID="${1:-}"

if [ -z "$UDID" ]; then
  # Auto-detect currently booted iOS simulator if none provided
  BOOTED_UDID="$(xcrun simctl list devices | grep -E "iPhone.*\(Booted\)" | head -n 1 | sed -E 's/.*\(([A-Fa-f0-9-]+)\).*/\1/' || true)"
  if [ -n "$BOOTED_UDID" ]; then
    echo "No simulator UDID specified. Detected booted simulator: $BOOTED_UDID"
    UDID="$BOOTED_UDID"
  else
    echo "Usage: $0 <simulator-udid>" >&2
    echo "Error: No simulator UDID passed and no booted iPhone simulator detected." >&2
    exit 64
  fi
fi

DEVICE_DATA_DIR="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data"
APP_GROUP_BASE="$DEVICE_DATA_DIR/Containers/Shared/AppGroup"

if [ ! -d "$APP_GROUP_BASE" ]; then
  echo "Error: AppGroup directory does not exist for simulator $UDID:" >&2
  echo "  $APP_GROUP_BASE" >&2
  echo "Ensure the simulator UDID is valid and has been booted at least once." >&2
  exit 1
fi

echo "================================================================="
echo "Cross-Process App Group Sharing Verification"
echo "  Simulator UDID: $UDID"
echo "  Target App Group: $REQUIRED_GROUP"
echo "================================================================="
echo ""

echo "==> Step 1: Running integration test on simulator $UDID..."
flutter test integration_test/widget_app_group_sync_test.dart -d "$UDID" --no-uninstall
echo "==> Integration test finished successfully."
echo ""

echo "==> Step 2: Scanning host-side App Group containers for $REQUIRED_GROUP..."
GROUP_CONTAINER=""

for meta in "$APP_GROUP_BASE"/*/.com.apple.mobile_container_manager.metadata.plist; do
  if [ -f "$meta" ]; then
    ident="$(plutil -extract MCMMetadataIdentifier raw "$meta" 2>/dev/null || true)"
    if [ "$ident" = "$REQUIRED_GROUP" ]; then
      GROUP_CONTAINER="$(dirname "$meta")"
      break
    fi
  fi
done

# Fallback grep search if plutil extract didn't match directly
if [ -z "$GROUP_CONTAINER" ]; then
  for meta in "$APP_GROUP_BASE"/*/.com.apple.mobile_container_manager.metadata.plist; do
    if [ -f "$meta" ] && grep -q "$REQUIRED_GROUP" "$meta" 2>/dev/null; then
      GROUP_CONTAINER="$(dirname "$meta")"
      break
    fi
  done
fi

if [ -z "$GROUP_CONTAINER" ]; then
  echo "FAIL: App Group container with identifier '$REQUIRED_GROUP' not found under:" >&2
  echo "  $APP_GROUP_BASE" >&2
  echo "This indicates that the app group container was not registered by CoreSimulator." >&2
  exit 1
fi

echo "PASS: Located App Group container at:"
echo "  $GROUP_CONTAINER"
echo ""

PLIST_FILE="$GROUP_CONTAINER/Library/Preferences/$REQUIRED_GROUP.plist"

if [ ! -f "$PLIST_FILE" ]; then
  echo "FAIL: Shared preferences file does not exist at:" >&2
  echo "  $PLIST_FILE" >&2
  echo "Contents of $GROUP_CONTAINER/Library:" >&2
  ls -la "$GROUP_CONTAINER/Library" >&2 || true
  exit 1
fi

echo "PASS: Located shared preferences plist at:"
echo "  $PLIST_FILE"
echo ""

echo "==> Step 3: Asserting synchronized note data directly from disk..."

HAS_PINNED="$(plutil -extract widget_has_pinned raw "$PLIST_FILE" 2>/dev/null || true)"
TITLE="$(plutil -extract widget_pinned_title raw "$PLIST_FILE" 2>/dev/null || true)"
ID="$(plutil -extract widget_pinned_id raw "$PLIST_FILE" 2>/dev/null || true)"
CHECKLIST="$(plutil -extract widget_pinned_checklist raw "$PLIST_FILE" 2>/dev/null || true)"

FAILED=0

if [ "$HAS_PINNED" != "true" ]; then
  echo "FAIL: widget_has_pinned is '$HAS_PINNED' (expected 'true')" >&2
  FAILED=1
else
  echo "PASS: widget_has_pinned == true"
fi

if [ "$TITLE" != "$EXPECTED_TITLE" ]; then
  echo "FAIL: widget_pinned_title is '$TITLE' (expected '$EXPECTED_TITLE')" >&2
  FAILED=1
else
  echo "PASS: widget_pinned_title == '$EXPECTED_TITLE'"
fi

if [ -z "$ID" ]; then
  echo "FAIL: widget_pinned_id is empty" >&2
  FAILED=1
else
  echo "PASS: widget_pinned_id == '$ID'"
fi

if [[ "$CHECKLIST" != *"Buy groceries for sync test"* ]]; then
  echo "FAIL: widget_pinned_checklist missing 'Buy groceries for sync test'" >&2
  FAILED=1
else
  echo "PASS: widget_pinned_checklist contains 'Buy groceries for sync test'"
fi

if [[ "$CHECKLIST" != *"Completed item 42"* ]]; then
  echo "FAIL: widget_pinned_checklist missing 'Completed item 42'" >&2
  FAILED=1
else
  echo "PASS: widget_pinned_checklist contains 'Completed item 42'"
fi

echo ""
if [ "$FAILED" -ne 0 ]; then
  echo "Raw plist dump for diagnosis:" >&2
  plutil -p "$PLIST_FILE" >&2 || true
  echo "App Group cross-process synchronization verification FAILED." >&2
  exit 1
fi

echo "================================================================="
echo "All host-side disk assertions PASSED."
echo "Verified that Runner app process wrote valid sync data to"
echo "the shared App Group container ($REQUIRED_GROUP)."
echo "================================================================="
exit 0
