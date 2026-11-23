#!/usr/bin/env bash
# Regenerates the Dart API client in app/packages/vouch_api from api/openapi.yaml.
# Run from anywhere. CI runs this and fails if the result differs from git,
# so the committed client always matches the contract.
set -euo pipefail

CLI_VERSION="2.42.0"        # @openapitools/openapi-generator-cli (npm wrapper)
GENERATOR_VERSION="7.27.0"  # openapi-generator (Java), pinned by the wrapper

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
spec="$repo/api/openapi.yaml"
out="$repo/app/packages/vouch_api"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The wrapper stores its config and the downloaded jar next to the cwd.
cd "$tmp"
npx --yes "@openapitools/openapi-generator-cli@${CLI_VERSION}" version-manager set "$GENERATOR_VERSION" >/dev/null
npx --yes "@openapitools/openapi-generator-cli@${CLI_VERSION}" generate \
  -g dart \
  -i "$spec" \
  -o "$tmp/out" \
  --additional-properties=pubName=vouch_api,pubLibrary=vouch_api,pubVersion=0.1.0 \
  --global-property=apiTests=false,modelTests=false,apiDocs=false,modelDocs=false \
  >/dev/null

# Keep only what the app needs: the library source and its pubspec.
rm -rf "$out"
mkdir -p "$out"
cp -R "$tmp/out/lib" "$out/lib"
cp "$tmp/out/pubspec.yaml" "$out/pubspec.yaml"
cp "$tmp/out/README.md" "$out/README.md"
# The firebasePush webhook is documentation for the push payload, not a call
# the app makes; the generator emits it as an unregistered part file.
rm -f "$out/lib/api/default_api.dart"
cat > "$out/analysis_options.yaml" <<'YAML'
# Generated code is not linted: its style is the generator's, and analyzer
# versions keep adding lints. The app's analysis_options excludes packages/.
analyzer:
  exclude:
    - "**"
YAML

# Format so `dart format --set-exit-if-changed` in CI is stable.
dart format "$out/lib" >/dev/null
echo "Generated $out from $spec (openapi-generator $GENERATOR_VERSION)"
