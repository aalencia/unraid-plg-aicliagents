#!/bin/bash
set -eu -o pipefail
base=/usr/local/emhttp/plugins/unraid-aicliagents
config=/boot/config/plugins/unraid-aicliagents
fail() { echo "AICLI_PREFLIGHT_BLOCKED: $*"; exit 1; }
[ -s "$base/src/includes/AICliAgentsManager.php" ] || fail "live plugin missing"
[ "$(tr -d '[:space:]' < "$base/src/.layout-version")" = 1 ] || fail "unexpected live layout"
[ ! -e "$config/.migration_required" ] || fail "pending migration"
echo "ACTIVE_SOURCE=$(readlink -f "$base/src")"
for spec in \
    includes/services/TerminalService.php:09d9e00b7170101cc7d59aa1e82621b3f66c47de8fa03140be83141837dff545 \
    includes/services/AutoLaunchService.php:8ef685960a4b1f436c86f9e66c809e505dd5fa1f47236e6206951878ea47002f; do
    path=${spec%%:*}; expected=${spec#*:}
    actual=$(sha256sum "$base/src/$path" | awk '{print $1}')
    echo "SOURCE_SHA256 $path $actual"
    [ "$actual" = "$expected" ] || fail "installed source differs from reviewed base: $path"
done
mapfile -t paths < <(/usr/bin/php -r '
    $c=parse_ini_file($argv[1]);
    foreach (["home_storage_path", "agent_storage_path"] as $k) {
        $p=$c[$k]??"";
        if (!$p || preg_match("/[\r\n]/",$p)) exit(1);
        echo $p, PHP_EOL;
    }' "$config/unraid-aicliagents.cfg")
[ "${#paths[@]}" -eq 2 ] || fail "cannot determine storage paths"
for path in "${paths[@]}"; do
    [ -d "$path" ] || fail "storage path unavailable"
    fs=$(findmnt -n -T "$path" -o FSTYPE)
    case "$fs" in ''|rootfs|tmpfs|overlay) fail "storage pool unavailable";; esac
    echo "STORAGE_PATH=$(readlink -f "$path")"
    findmnt -n -T "$path" -o TARGET,SOURCE,FSTYPE
    stat -Lc 'STORAGE_STAT device=%d inode=%i mode=%a uid=%u gid=%g mtime=%Y' "$path"
done
for lock in /var/run/aicli-bake-*.lock /var/run/aicli-consolidate*.lock; do
    [ -e "$lock" ] || continue
    exec {fd}<"$lock"
    flock -n "$fd" || fail "storage operation in progress"
    flock -u "$fd"
    exec {fd}<&-
done
"$base/bin/tmux" -V || fail "current tmux unavailable"
sha256sum /boot/config/plugins/unraid-aicliagents.plg "$config/unraid-aicliagents.cfg"
df -Pk "$base" "$config"
echo 'AICLI_PREFLIGHT_PASS: same-layout source and mounted storage verified; no plugin files or storage changed.'
# The diagnostic descriptor must not be registered as an installed plugin.
# Unraid reports this deliberate nonzero result; the PASS marker is the result.
exit 1
