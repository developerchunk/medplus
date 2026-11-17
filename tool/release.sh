#!/usr/bin/env bash
# Publishes a new MedBillings version to the shop PC(s).
#
#   tool/release.sh patch "Fix bill print margin"     1.1.0 -> 1.1.1
#   tool/release.sh minor "Add outside medicines"     1.1.0 -> 1.2.0
#
# Bumps the version in pubspec.yaml (and the build number), commits, tags vX.Y.Z
# and pushes. GitHub then builds, signs and publishes the release
# (.github/workflows/linux-deb.yml); installed apps pick it up within a few hours
# and show "Restart & update". The message becomes the "What's new" text.
set -euo pipefail
cd "$(dirname "$0")/.."

part=${1:-}
notes=${2:-}
case "$part" in patch|minor|major) ;; *) echo "usage: tool/release.sh patch|minor|major \"what changed\"" >&2; exit 2 ;; esac
[ -n "$notes" ] || { echo "say what changed, e.g. tool/release.sh patch \"Fix print margin\"" >&2; exit 2; }
[ -z "$(git status --porcelain)" ] || { echo "commit or stash your changes first" >&2; exit 1; }

cur=$(sed -nE 's/^version:[[:space:]]*([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+).*/\1 \2 \3 \4/p' pubspec.yaml)
read -r ma mi pa build <<<"$cur"
case "$part" in
  major) ma=$((ma + 1)); mi=0; pa=0 ;;
  minor) mi=$((mi + 1)); pa=0 ;;
  patch) pa=$((pa + 1)) ;;
esac
build=$((build + 1))
new="$ma.$mi.$pa"

sed -i.bak -E "s/^version:.*/version: $new+$build/" pubspec.yaml && rm pubspec.yaml.bak
git add pubspec.yaml
git commit -q -m "MedBillings $new

$notes"
git tag -a "v$new" -m "$notes"
git push origin HEAD "v$new"
echo "Pushed v$new. GitHub is building it now; shop PCs will offer the update once the release appears."
