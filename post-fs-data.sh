#!/system/bin/sh
# Early boot: Magisk/KSU systemless overlay for /system/etc/security/cacerts
# On Android < 14 this is the primary trust store. On 14+ Conscrypt APEX wins;
# service.sh handles that path after boot_completed.

MODDIR=${0%/*}
# shellcheck source=/dev/null
. "$MODDIR/common.sh"

echo "" >"$LOG_FILE"
log "=== post-fs-data.sh start ==="

# Magisk auto-mounts $MODDIR/system over /system. Populate a filtered copy so
# the overlay hides the bad roots without needing a full tmpfs replace yet.
mkdir -p "$MODDIR$SYS_CERT_DIR"

# Prefer APEX certs as the base when present (more up-to-date on modern devices),
# otherwise fall back to the system store.
SRC=""
if [ -d "$APEX_CERT_DIR" ] && [ -n "$(ls -A "$APEX_CERT_DIR" 2>/dev/null)" ]; then
  SRC="$APEX_CERT_DIR"
  log "Base store: APEX $APEX_CERT_DIR"
elif [ -d "$SYS_CERT_DIR" ] && [ -n "$(ls -A "$SYS_CERT_DIR" 2>/dev/null)" ]; then
  SRC="$SYS_CERT_DIR"
  log "Base store: system $SYS_CERT_DIR"
else
  log "ERROR: no CA certificate directory found"
  exit 0
fi

# Snapshot into module system overlay path
rm -rf "$MODDIR$SYS_CERT_DIR"
mkdir -p "$MODDIR$SYS_CERT_DIR"
cp -p "$SRC"/* "$MODDIR$SYS_CERT_DIR"/ 2>/dev/null || cp "$SRC"/* "$MODDIR$SYS_CERT_DIR"/
remove_blocked_from_dir "$MODDIR$SYS_CERT_DIR"
fix_perms "$MODDIR$SYS_CERT_DIR"

# Also prepare WORK_DIR for service.sh bind-mounts
build_filtered_store "$SRC" || true

# On devices without Magisk systemless mount of this path (or if overlay is
# empty due to magic mount quirks), try a direct removal via replace/remove
# placeholders: Magisk treats files named .replace specially is NOT needed;
# empty delete is done by omitting the file from the overlay while keeping
# sibling certs — already done above.

log "=== post-fs-data.sh done ==="
