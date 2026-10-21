#!/system/bin/sh
# Late start: re-apply cacerts-removed after user profiles exist,
# inject filtered store into Conscrypt APEX mount namespaces.

MODDIR=${0%/*}
# shellcheck source=/dev/null
. "$MODDIR/common.sh"

log "=== service.sh start ==="

i=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
  sleep 1
  i=$((i + 1))
  [ "$i" -gt 120 ] && break
done
sleep 5

install_blocklist
notify_keychain
inject_conscrypt_overlay

# Keep re-binding if zygote restarts
(
  while true; do
    sleep 10
    [ -d "$APEX_CERT_DIR" ] || continue
    _bind="$WORK_DIR"
    [ -d "$SYS_CERT_DIR" ] && [ -n "$(ls -A "$SYS_CERT_DIR" 2>/dev/null)" ] && _bind="$SYS_CERT_DIR"
    [ -d "$_bind" ] || continue
    for name in zygote zygote64; do
      for zp in $(pidof "$name" 2>/dev/null); do
        if ! grep -q " $APEX_CERT_DIR " "/proc/$zp/mountinfo" 2>/dev/null; then
          echo "$(date '+%Y-%m-%d %H:%M:%S') re-inject zygote $zp" >>"$LOG_FILE"
          bind_into_pid "$zp" "$_bind" "$APEX_CERT_DIR"
          children=$(ps -o PID= -P "$zp" 2>/dev/null)
          for pid in $children; do
            bind_into_pid "$pid" "$_bind" "$APEX_CERT_DIR" &
          done
          wait
        fi
      done
    done
  done
) &

log "=== service.sh done ==="
