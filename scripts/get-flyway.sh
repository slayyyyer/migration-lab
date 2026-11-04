#!/usr/bin/env bash
# Download the pinned Flyway CLI from Maven Central into .tools/.
# Pinned rather than "latest" so a scenario that passes today still passes next month.
set -euo pipefail

FLYWAY_VERSION="${FLYWAY_VERSION:-13.12.0}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="$root/.tools"
mkdir -p "$target"

if [ -x "$target/flyway-$FLYWAY_VERSION/flyway" ]; then
  echo "flyway $FLYWAY_VERSION already present"
  exit 0
fi

url="https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/${FLYWAY_VERSION}/flyway-commandline-${FLYWAY_VERSION}.zip"
echo "downloading $url"
curl -fsSL "$url" -o "$target/flyway.zip"
unzip -q -o "$target/flyway.zip" -d "$target"
rm -f "$target/flyway.zip"
chmod +x "$target/flyway-$FLYWAY_VERSION/flyway"

echo "flyway installed at $target/flyway-$FLYWAY_VERSION/flyway"
