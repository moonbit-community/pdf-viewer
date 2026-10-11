#!/usr/bin/env bash
set -euo pipefail
# Official versioned archives, checked against the repository's immutable
# checksums. Install into a new directory; never overwrite another toolchain.
ci_moon_root=${1:?usage: install_moon.sh NEW_INSTALL_DIRECTORY}
if [[ -e "$ci_moon_root" ]]; then
  echo "Installation directory already exists: $ci_moon_root" >&2
  exit 1
fi
case "$(uname -ms)" in
  'Linux x86_64') ci_moon_platform=linux-x86_64 ;;
  'Darwin arm64') ci_moon_platform=darwin-aarch64 ;;
  *) echo 'Unsupported CI platform' >&2; exit 1 ;;
esac
ci_moon_version=$(node -p "require('./tools/ci/toolchain.json').moonbit")
ci_moon_archive_version=${ci_moon_version//+/%2B}
ci_moon_expected=$(node -p "require('./tools/ci/toolchain.json')['$ci_moon_platform'+'_sha256']")
ci_core_expected=$(node -p "require('./tools/ci/toolchain.json').core_sha256")
mkdir -p "$ci_moon_root/lib"
curl -fLsS --retry 3 "https://cli.moonbitlang.com/binaries/$ci_moon_archive_version/moonbit-$ci_moon_platform.tar.gz" -o "$ci_moon_root/toolchain.tar.gz"
curl -fLsS --retry 3 "https://cli.moonbitlang.com/cores/core-$ci_moon_archive_version.tar.gz" -o "$ci_moon_root/core.tar.gz"
verify() {
  local ci_digest
  ci_digest=$(shasum -a 256 "$1")
  [[ ${ci_digest%% *} == "$2" ]] || { echo "Checksum mismatch: $1" >&2; exit 1; }
}
verify "$ci_moon_root/toolchain.tar.gz" "$ci_moon_expected"
verify "$ci_moon_root/core.tar.gz" "$ci_core_expected"
tar -xzf "$ci_moon_root/toolchain.tar.gz" -C "$ci_moon_root"
tar -xzf "$ci_moon_root/core.tar.gz" -C "$ci_moon_root/lib"
chmod +x "$ci_moon_root"/bin/* "$ci_moon_root/bin/internal/tcc"
export PATH="$ci_moon_root/bin:$PATH"
export MOON_HOME="$ci_moon_root"
moon update
moon -C "$ci_moon_root/lib/core" bundle --warn-list -a --all
moon -C "$ci_moon_root/lib/core" bundle --warn-list -a --target wasm-gc --quiet
moon version --all
