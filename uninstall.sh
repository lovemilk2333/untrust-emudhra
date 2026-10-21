#!/system/bin/sh
MODDIR=${0%/*}
# shellcheck source=/dev/null
. "$MODDIR/common.sh"

echo "" >"$LOG_FILE"
log "=== uninstall.sh ==="
uninstall_blocklist
rm -rf "$MARKER_DIR" "$WORK_DIR" "$MODDIR/system"
rm -f "$LOG_FILE"
exit 0
