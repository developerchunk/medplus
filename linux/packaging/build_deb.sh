#!/usr/bin/env bash
# Builds MedBillings for Linux and packs it into a .deb installer
# (dist/medbillings_<version>_amd64.deb). On Linux Mint / Ubuntu, double-click
# the .deb to install: it adds MedBillings to the menu, puts an icon on the
# desktop, starts it automatically at login and pulls in what it needs.
#
# Must run on 64-bit Linux (Ubuntu 22.04+/Mint 21+): Flutter can't build Linux
# apps on macOS. Build on the oldest Ubuntu you need to support -- a .deb built
# on Ubuntu 22.04 runs on Mint 21 and 22; one built on 24.04 needs Mint 22+.
# No Linux machine? Push to GitHub: .github/workflows/linux-deb.yml builds it.
#
# Usage: linux/packaging/build_deb.sh [options]
#   --install-deps   apt-get install the Linux build tools first (uses sudo)
#   --skip-build     package the existing build/linux/x64/release/bundle
#   --bundle DIR     package DIR instead of the Flutter build output
#   --no-autostart   don't open MedBillings automatically at login
set -euo pipefail

APP_ID=com.developerstring.medical
PKG=medbillings

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
HERE="$ROOT/linux/packaging"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
OUT="$ROOT/dist"

INSTALL_DEPS=0 BUILD=1 AUTOSTART=1
while [ $# -gt 0 ]; do
  case "$1" in
    --install-deps) INSTALL_DEPS=1 ;;
    --skip-build) BUILD=0 ;;
    --bundle) BUNDLE=$(cd "${2:?--bundle needs a directory}" && pwd); BUILD=0; shift ;;
    --no-autostart) AUTOSTART=0 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

die() { echo "error: $*" >&2; exit 1; }

# pubspec "version: 1.2.3+4" -> Debian "1.2.3-4"
PUB_VERSION=$(sed -nE 's/^version:[[:space:]]*([^[:space:]]+).*/\1/p' "$ROOT/pubspec.yaml")
[ -n "$PUB_VERSION" ] || die "no version: line in pubspec.yaml"
DEB_VERSION=${PUB_VERSION/+/-}

if [ "$BUILD" = 1 ]; then
  [ "$(uname -s)" = Linux ] || die "build on Linux (Flutter can't build Linux apps on $(uname -s)); see the top of this script"
  [ "$(uname -m)" = x86_64 ] || die "build on a 64-bit Intel/AMD machine (this one is $(uname -m))"
  if [ "$INSTALL_DEPS" = 1 ]; then
    sudo apt-get update
    sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev \
      liblzma-dev libstdc++-12-dev curl git unzip xz-utils zip dpkg-dev
  fi
  command -v flutter >/dev/null || die "flutter not found on PATH (https://docs.flutter.dev/get-started/install/linux)"
  # The build downloads SQLite and pdfium (for printing), so it needs internet.
  (cd "$ROOT" && flutter pub get && flutter build linux --release)
fi

[ -x "$BUNDLE/MedBillings" ] || die "no MedBillings executable in $BUNDLE (build first, or drop --skip-build)"
command -v dpkg-deb >/dev/null || die "dpkg-deb not found (sudo apt-get install dpkg-dev)"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/${PKG}_${DEB_VERSION}_amd64"
umask 022

# App files
mkdir -p "$STAGE/opt/$PKG" "$STAGE/usr/bin" "$STAGE/usr/share/applications"
cp -R "$BUNDLE/." "$STAGE/opt/$PKG/"
ln -s "/opt/$PKG/MedBillings" "$STAGE/usr/bin/$PKG"

# Menu entry and icons
cp "$HERE/$APP_ID.desktop" "$STAGE/usr/share/applications/"
for size in 128 256 512; do
  dir="$STAGE/usr/share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$dir"
  cp "$HERE/icons/$size.png" "$dir/$APP_ID.png"
done

# Open at login (the shop PC should land straight in billing)
CONFFILES=""
if [ "$AUTOSTART" = 1 ]; then
  mkdir -p "$STAGE/etc/xdg/autostart"
  { cat "$HERE/$APP_ID.desktop"; echo "X-GNOME-Autostart-enabled=true"; } \
    > "$STAGE/etc/xdg/autostart/$APP_ID.desktop"
  CONFFILES="/etc/xdg/autostart/$APP_ID.desktop"
fi

# Package metadata and install scripts
mkdir -p "$STAGE/DEBIAN"
cp "$HERE/postinst" "$HERE/postrm" "$STAGE/DEBIAN/"
[ -z "$CONFFILES" ] || echo "$CONFFILES" > "$STAGE/DEBIAN/conffiles"
INSTALLED_KB=$(du -sk "$STAGE" | cut -f1)
cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PKG
Version: $DEB_VERSION
Architecture: amd64
Maintainer: MedBillings <duosagesdev@gmail.com>
Installed-Size: $INSTALLED_KB
Depends: libgtk-3-0t64 | libgtk-3-0, zenity, xdg-user-dirs, xdg-utils
Recommends: cups
Section: misc
Priority: optional
Description: MedBillings - billing and stock for a medical shop
 Billing, stock entry, expiry tracking and credit customers for a small
 retail pharmacy. All data stays on this computer in Documents/MedBillings.
EOF

# Normalise permissions (files copied from macOS or odd umasks)
find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE" -type f ! -perm -u+x -exec chmod 644 {} +
find "$STAGE" -type f -perm -u+x -exec chmod 755 {} +
chmod 755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"
chmod 644 "$STAGE/DEBIAN/control"
[ -z "$CONFFILES" ] || chmod 644 "$STAGE/DEBIAN/conffiles"

mkdir -p "$OUT"
DEB="$OUT/${PKG}_${DEB_VERSION}_amd64.deb"
dpkg-deb --root-owner-group -Zxz --build "$STAGE" "$DEB" >/dev/null
echo "Built $DEB ($(du -h "$DEB" | cut -f1))"
