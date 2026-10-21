#!/system/bin/sh
# Late start: inject filtered CA store into Conscrypt APEX (Android 14+)
# and keep zygote / app mount namespaces updated.

MODDIR=${0%/*}
# shellcheck source=/dev/null
. "$MODDIR/common.sh"

log "=== service.sh start ==="

# Wait until boot is far enough that zygote and APEX are up
i=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
  sleep 1
  i=$((i + 1))
  [ "$i" -gt 120 ] && break
done
sleep 2

# Ensure we have a filtered working copy
if [ ! -d "$WORK_DIR" ] || [ -z "$(ls -A "$WORK_DIR" 2>/dev/null)" ]; then
  if [ -d "$APEX_CERT_DIR" ] && [ -n "$(ls -A "$APEX_CERT_DIR" 2>/dev/null)" ]; then
    build_filtered_store "$APEX_CERT_DIR"
  elif [ -d "$MODDIR$SYS_CERT_DIR" ] && [ -n "$(ls -A "$MODDIR$SYS_CERT_DIR" 2>/dev/null)" ]; then
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"
    cp -p "$MODDIR$SYS_CERT_DIR"/* "$WORK_DIR"/ 2>/dev/null || cp "$MODDIR$SYS_CERT_DIR"/* "$WORK_DIR"/
    fix_perms "$WORK_DIR"
  elif [ -d "$SYS_CERT_DIR" ]; then
    build_filtered_store "$SYS_CERT_DIR"
  else
    log "ERROR: cannot build filtered CA store"
    exit 0
  fi
fi

CERT_SRC="$WORK_DIR"
if [ ! -d "$CERT_SRC" ] || [ -z "$(ls -A "$CERT_SRC" 2>/dev/null)" ]; then
  log "ERROR: filtered store empty"
  exit 0
fi

# --- Replace /system/etc/security/cacerts with tmpfs + filtered certs ---
mount -t tmpfs -o mode=755 tmpfs "$SYS_CERT_DIR" 2>/dev/null \
  || mount -t tmpfs tmpfs "$SYS_CERT_DIR" 2>/dev/null \
  || {
    log "WARN: could not mount tmpfs on $SYS_CERT_DIR; trying in-place remove"
    remove_blocked_from_dir "$SYS_CERT_DIR"
  }

if mount 2>/dev/null | grep -q " on $SYS_CERT_DIR "; then
  cp -p "$CERT_SRC"/* "$SYS_CERT_DIR"/ 2>/dev/null || cp "$CERT_SRC"/* "$SYS_CERT_DIR"/
  fix_perms "$SYS_CERT_DIR"
  log "tmpfs applied on $SYS_CERT_DIR ($(ls "$SYS_CERT_DIR" 2>/dev/null | wc -l) certs)"
fi

BIND_SRC="$CERT_SRC"
if [ -d "$SYS_CERT_DIR" ] && [ -n "$(ls -A "$SYS_CERT_DIR" 2>/dev/null)" ]; then
  BIND_SRC="$SYS_CERT_DIR"
fi

# Bind filtered store into a process mount namespace
do_bind_pid() {
  _pid="$1"
  [ -n "$_pid" ] || return 0
  [ -d "/proc/$_pid" ] || return 0

  if [ -x /system/bin/nsenter ]; then
    /system/bin/nsenter --mount=/proc/$_pid/ns/mnt -- \
      /bin/mount --bind "$BIND_SRC" "$APEX_CERT_DIR" 2>/dev/null && return 0
    /system/bin/nsenter --mount=/proc/$_pid/ns/mnt -- \
      mount --bind "$BIND_SRC" "$APEX_CERT_DIR" 2>/dev/null && return 0
  fi
  if command -v nsenter >/dev/null 2>&1; then
    nsenter --mount=/proc/$_pid/ns/mnt -- \
      mount --bind "$BIND_SRC" "$APEX_CERT_DIR" 2>/dev/null && return 0
  fi
  return 1
}

inject_conscrypt_once() {
  if [ ! -d "$APEX_CERT_DIR" ]; then
    log "No Conscrypt APEX cacerts dir; skipping APEX inject"
    return 0
  fi

  for name in zygote zygote64; do
    for zp in $(pidof "$name" 2>/dev/null); do
      if do_bind_pid "$zp"; then
        log "Bound into $name pid $zp"
      else
        log "WARN: bind failed for $name pid $zp"
      fi

      # Already-running app children
      children=$(ps -o PID= -P "$zp" 2>/dev/null)
      if [ -z "$children" ]; then
        children=$(ps 2>/dev/null | awk -v PPID="$zp" '$3 == PPID { print $2 }')
      fi
      for pid in $children; do
        do_bind_pid "$pid" &
      done
      wait
    done
  done
  log "Conscrypt inject pass complete"
}

inject_conscrypt_once

# Re-inject when zygote restarts (crash / soft reboot)
(
  # Re-source not needed: BIND_SRC and functions are inherited in most Android sh,
  # but mksh may not export functions. Inline minimal re-bind instead.
  while true; do
    sleep 8
    [ -d "$APEX_CERT_DIR" ] || continue
    need=0
    for name in zygote zygote64; do
      for zp in $(pidof "$name" 2>/dev/null); do
        if ! grep -q " $APEX_CERT_DIR " "/proc/$zp/mountinfo" 2>/dev/null; then
          need=1
          break 2
        fi
      done
    done
    if [ "$need" = "1" ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') zygote missing bind; re-injecting" >>"$LOG_FILE"
      for name in zygote zygote64; do
        for zp in $(pidof "$name" 2>/dev/null); do
          if [ -x /system/bin/nsenter ]; then
            /system/bin/nsenter --mount=/proc/$zp/ns/mnt -- \
              /bin/mount --bind "$BIND_SRC" "$APEX_CERT_DIR" 2>/dev/null \
              || /system/bin/nsenter --mount=/proc/$zp/ns/mnt -- \
                mount --bind "$BIND_SRC" "$APEX_CERT_DIR" 2>/dev/null
          fi
          children=$(ps -o PID= -P "$zp" 2>/dev/null)
          if [ -z "$children" ]; then
            children=$(ps 2>/dev/null | awk -v PPID="$zp" '$3 == PPID { print $2 }')
          fi
          for pid in $children; do
            [ -d "/proc/$pid" ] || continue
            /system/bin/nsenter --mount=/proc/$pid/ns/mnt -- \
              /bin/mount --bind "$BIND_SRC" "$APEX_CERT_DIR" 2>/dev/null &
          done
          wait
        done
      done
    fi
  done
) &

log "=== service.sh done (monitor running) ==="
