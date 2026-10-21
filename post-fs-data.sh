#!/system/bin/sh
# Early boot: cacerts-removed + Magisk systemless CA overlay (roots omitted).

MODDIR=${0%/*}
# shellcheck source=/dev/null
. "$MODDIR/common.sh"

echo "" >"$LOG_FILE"
log "=== post-fs-data.sh v1.2.0 ==="

install_blocklist
prepare_magisk_overlay

log "=== post-fs-data.sh done ==="
