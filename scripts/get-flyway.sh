#!/usr/bin/env bash
# Download the pinned Flyway CLI into .tools/ and record the binary path.
#
# Since Flyway 13 the CLI is published as platform archives on GitHub Releases;
# Maven Central only carries the plain jar for these versions. Pinning the version
# rather than taking "latest" means a scenario that passes today still passes next month.
set -euo pipefail

FLYWAY_VERSION="${FLYWAY_VERSION:-13.12.0}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="$root/.tools"
mkdir -p "$target"

marker="$target/flyway-bin"
if [ -s "$marker" ] && [ -e "$(cat "$marker")" ]; then
  case "$(cat "$marker")" in
    *.cmd)
      case "$(uname -s)" in
        MINGW* | MSYS* | CYGWIN*) echo "flyway $FLYWAY_VERSION already present at $(cat "$marker")"; exit 0 ;;
        # A Windows launcher recorded here is unusable on this platform; fall through and
        # pick the right one rather than failing with "Permission denied" at run time.
        *) echo "ignoring the Windows launcher recorded at $(cat "$marker")" ;;
      esac
      ;;
    *) echo "flyway $FLYWAY_VERSION already present at $(cat "$marker")"; exit 0 ;;
  esac
fi

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)                asset="linux-x64.tar.gz" ;;
  Linux-aarch64|Linux-arm64)   asset="linux-arm64.tar.gz" ;;
  Darwin-arm64)                asset="macosx-arm64.tar.gz" ;;
  Darwin-x86_64)               asset="macosx-x64.tar.gz" ;;
  MINGW*|MSYS*|CYGWIN*)        asset="windows-x64.zip" ;;
  *) echo "unsupported platform: $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

archive="$target/flyway-download.$([ "${asset##*.}" = "zip" ] && echo zip || echo tar.gz)"
url="https://github.com/flyway/flyway/releases/download/flyway-${FLYWAY_VERSION}/flyway-commandline-${FLYWAY_VERSION}-${asset}"

echo "downloading $url"
if ! curl -fsSL "$url" -o "$archive"; then
  echo "could not download Flyway ${FLYWAY_VERSION} for ${asset}" >&2
  echo "check https://github.com/flyway/flyway/releases/tag/flyway-${FLYWAY_VERSION}" >&2
  exit 1
fi

case "$archive" in
  *.zip) unzip -q -o "$archive" -d "$target" ;;
  *)     tar -xzf "$archive" -C "$target" ;;
esac
rm -f "$archive"

# Choose the launcher for this platform explicitly. The archives can carry both, and
# `find ... | head -1` returns directory order, so the Windows `flyway.cmd` can win on
# Linux — where executing it fails with "Permission denied" and every scenario fails.
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) launcher="flyway.cmd" ;;
  *) launcher="flyway" ;;
esac
binary="$(find "$target" -maxdepth 3 -type f -name "$launcher" | head -1)"
if [ -z "$binary" ]; then
  binary="$(find "$target" -maxdepth 3 -type f \( -name flyway -o -name flyway.cmd \) | head -1)"
fi
if [ -z "$binary" ]; then
  echo "downloaded Flyway ${FLYWAY_VERSION} but found no launcher in $target" >&2
  exit 1
fi
[ "${binary##*.}" = "cmd" ] || chmod +x "$binary"

printf '%s' "$binary" >"$marker"
echo "flyway installed at $binary"
