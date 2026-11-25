#!/bin/sh
set -eu

version=2.38.2
destination=${1:?Usage: install-dbmate.sh DESTINATION}

case "$(uname -s)/$(uname -m)" in
  Darwin/arm64)
    asset=macos-arm64
    digest=3cbd137e01bd068e9f0183a2da951cedfae6dbad0387f45d56a626abf4bb237a ;;
  Darwin/x86_64)
    asset=macos-amd64
    digest=2d504d0150dd56d3af7ed9698547942d62f144df02fed39d8d65347145d546ee ;;
  Linux/aarch64|Linux/arm64)
    asset=linux-arm64
    digest=5d70ac9a7d337daa79d3f9821cf8bab3fbcfc41b5167557d9e096b8a31a61743 ;;
  Linux/x86_64)
    asset=linux-amd64
    digest=4c6059e4e52558605d39e8c8075f3b15f96cac293043c0c71bb464d8950f235c ;;
  Linux/armv7l)
    asset=linux-arm
    digest=1240bc88a3ded890cbb484a6b0270d8349c4f76d2783e73e4988a9464ce2c0de ;;
  Linux/i386|Linux/i486|Linux/i586|Linux/i686)
    asset=linux-386
    digest=1fe8a9656f8f859764c5db19121f198f35ef160da18da1ac4ba869d625a27e15 ;;
  *)
    echo "Automatic dbmate installation is not supported on this platform. Install dbmate $version or later separately." >&2
    exit 1 ;;
esac

if command -v sha256sum >/dev/null 2>&1; then
  checksum() { sha256sum < "$1"; }
elif command -v shasum >/dev/null 2>&1; then
  checksum() { shasum -a 256 < "$1"; }
else
  echo "Installing dbmate requires sha256sum or shasum." >&2
  exit 1
fi

matches_release() {
  result=$(checksum "$1") || return 1
  [ "${result%% *}" = "$digest" ]
}

if [ -f "$destination" ] && [ -x "$destination" ] && matches_release "$destination"; then
  exit 0
fi
if [ -d "$destination" ]; then
  echo "The dbmate destination is a directory: $destination" >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "Downloading dbmate requires curl." >&2
  exit 1
fi

mkdir -p "$(dirname "$destination")"
temporary=$(mktemp "$destination.XXXXXXXX")
trap 'rm -f "$temporary"' 0
trap 'exit 1' HUP INT TERM

echo "Downloading dbmate $version for $asset"
curl --disable --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
  --connect-timeout 10 --max-time 120 --retry 2 \
  --output "$temporary" "https://github.com/amacneil/dbmate/releases/download/v$version/dbmate-$asset"
if ! matches_release "$temporary"; then
  echo "Downloaded dbmate $version failed checksum verification." >&2
  exit 1
fi
chmod 755 "$temporary"
mv -f "$temporary" "$destination"
