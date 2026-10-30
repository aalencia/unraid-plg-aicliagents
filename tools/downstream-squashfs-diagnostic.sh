#!/bin/bash
# Creates and removes only a private /tmp directory. No plugin/user files changed.
set -u -o pipefail
archive=/boot/config/plugins/unraid-aicliagents/squashfs-tools-4.5-x86_64-2.txz
expected=1615c7198fe92513fb47326c53a52031448dc9c2b7858382a0d2a1d39bd95b45
actual=$(sha256sum "$archive" | awk '{print $1}') || exit 1
echo "SQUASH_ARCHIVE_SHA256=$actual"
if [ "$actual" != "$expected" ]; then
    echo 'AICLI_SQUASH_DIAGNOSTIC_BLOCKED: cached archive missing or does not match the pinned release.'
    exit 1
fi
scratch=$(mktemp -d /tmp/aicli-runtime-diagnostic.XXXXXX) || exit 1
cleanup() {
    case "${scratch:-}" in /tmp/aicli-runtime-diagnostic.*) rm -rf -- "$scratch" ;; esac
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
tar -xf "$archive" -C "$scratch" --no-same-owner usr/bin/mksquashfs usr/bin/unsquashfs || exit 1
for tool in mksquashfs unsquashfs; do
    file="$scratch/usr/bin/$tool"
    echo "SQUASH_TOOL=$tool"
    sha256sum "$file" || exit 1
    if command -v ldd >/dev/null 2>&1; then
        ldd "$file" 2>&1
        rc=$?
        echo "LDD_EXIT=$rc"
    else
        echo 'LDD_UNAVAILABLE=1'
    fi
    timeout 10 "$file" -version 2>&1
    rc=$?
    echo "VERSION_EXIT=$rc"
done
echo 'AICLI_SQUASH_DIAGNOSTIC_COMPLETE: inspected exact pinned executables in private temporary storage; plugin and HOME/Agent Storage unchanged.'
# The diagnostic descriptor must not be registered as an installed plugin.
exit 1
