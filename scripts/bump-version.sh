#!/usr/bin/env bash
set -euo pipefail

# Bump the marketing version (MARKETING_VERSION) in the Xcode project.
# Usage: bump-version.sh [major|minor|patch]
# Default: minor

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PBXPROJ="$ROOT/ios/spackle/spackle.xcodeproj/project.pbxproj"
COMPONENT="${1:-minor}"

CURRENT=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= *//;s/;.*//')
if [[ -z "$CURRENT" ]]; then
  echo "Could not read MARKETING_VERSION from pbxproj" >&2
  exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
PATCH="${PATCH:-0}"

case "$COMPONENT" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
  *)
    echo "Usage: bump-version.sh [major|minor|patch]" >&2
    exit 1
    ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"
echo "Bumping version: $CURRENT -> $NEW_VERSION"
sed -i '' "s/MARKETING_VERSION = $CURRENT;/MARKETING_VERSION = $NEW_VERSION;/g" "$PBXPROJ"
echo "Done. Marketing version is now $NEW_VERSION"
