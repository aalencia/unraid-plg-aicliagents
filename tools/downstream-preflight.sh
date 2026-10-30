# Downstream release: only an existing, same-layout plugin may be updated.
# Never convert storage or consume a migration request as part of this fix.
export AICLI_PRESERVE_STORAGE=1
export AICLI_RUNTIME_ONLY=0
if [ -s "$EMHTTP_DEST/src/includes/AICliAgentsManager.php" ]; then
    export AICLI_RUNTIME_ONLY=1
fi
_downstream_layout="$_OLD_LV"
if [ "$_downstream_layout" = "0" ] && [ -s "$CONFIG_DIR/.layout-version" ]; then
    _downstream_layout=$(tr -d '[:space:]' < "$CONFIG_DIR/.layout-version")
fi
if [ "$_downstream_layout" != "1" ] || [ -e "$CONFIG_DIR/.migration_required" ]; then
    echo "ERROR: runtime fix requires existing storage layout 1 with no pending migration; installation stopped." >&2
    exit 1
fi
# A reboot has no RAM plugin directory, but layout 1 is already installed.
# Keep cleanup on its non-destructive same-layout branch during reconstruction.
export OLD_LAYOUT_VERSION=1
export UPGRADE_MODE=1
if [ "$AICLI_RUNTIME_ONLY" = "1" ]; then
    _cfg="$CONFIG_DIR/unraid-aicliagents.cfg"
    if [ ! -s "$_cfg" ]; then
        echo "ERROR: existing plugin configuration missing; installation stopped." >&2
        exit 1
    fi
    mapfile -t _storage_paths < <(/usr/bin/php -r '
        $c=parse_ini_file($argv[1]);
        foreach (["home_storage_path", "agent_storage_path"] as $k) {
            $p=$c[$k] ?? "";
            if (!$p || preg_match("/[\r\n]/",$p)) exit(1);
            echo $p, PHP_EOL;
        }' "$_cfg")
    if [ "${#_storage_paths[@]}" -ne 2 ]; then
        echo "ERROR: cannot verify configured HOME and Agent Storage paths; installation stopped." >&2
        exit 1
    fi
    for _storage_path in "${_storage_paths[@]}"; do
        if [ ! -d "$_storage_path" ]; then
            echo "ERROR: configured storage path is unavailable; installation stopped." >&2
            exit 1
        fi
        _storage_fs=$(findmnt -n -T "$_storage_path" -o FSTYPE 2>/dev/null)
        case "$_storage_fs" in
            ""|rootfs|tmpfs|overlay)
                echo "ERROR: configured storage resolves to an unavailable pool; installation stopped." >&2
                exit 1 ;;
        esac
    done
    _rollback="$CONFIG_DIR/downstream-rollback/2026.10.29.01"
    mkdir -p "$_rollback" || exit 1
    # Preserve the original descriptor once; never replace the rollback copy
    # with this downstream descriptor on a repeated install.
    if [ ! -e "$_rollback/unraid-aicliagents.plg" ]; then
        cp /boot/config/plugins/unraid-aicliagents.plg "$_rollback/unraid-aicliagents.plg" || exit 1
        readlink -f "$EMHTTP_DEST/src" > "$_rollback/prior-source-path" || exit 1
        sha256sum "$_rollback/unraid-aicliagents.plg" > "$_rollback/SHA256SUMS" || exit 1
    fi
fi
