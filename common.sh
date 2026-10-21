#!/system/bin/sh
# Block compromised eMudhra CAs without wiping the real system partition.
#
# Android has TWO disable paths:
# 1) TrustedCertificateStore  -> /data/misc/keychain/cacerts-removed
#    Matches by exact X509Certificate.equals() (KeyChain writes DER).
# 2) SystemCertificateSource  -> /data/misc/user/<id>/cacerts-removed
#    Matches by FILENAME only (used by NetworkSecurityConfig / most apps).
#
# Intermediates are usually NOT in the system CA dir, so disabling them via
# cacerts-removed alone does nothing for TLS. Blocking the issuing / cross-
# signing ROOTS is what breaks the compromised chains.
#
# Overlay: Magisk/KSU also hides those root files from the runtime CA dir
# (system + Conscrypt APEX) so TLS fails even if cacerts-removed is ignored.

MODDIR="${MODDIR:-${0%/*}}"
BLOCKLIST_DIR="$MODDIR/blocklist"
BLOCKLIST_DER_DIR="$MODDIR/blocklist-der"
MARKER_DIR="$MODDIR/installed-removed"
WORK_DIR="$MODDIR/cacerts-work"
LOG_FILE="$MODDIR/log.txt"

SYS_CERT_DIR=/system/etc/security/cacerts
APEX_CERT_DIR=/apex/com.android.conscrypt/cacerts
KEYCHAIN_REMOVED=/data/misc/keychain/cacerts-removed

# Roots we disable (Android subject_hash_old). Intermediates are shipped in
# blocklist for completeness but only roots present on-device matter for TLS.
ROOT_HASHES="b74d2bd5 75680d2e 60a9fcc6 f468719d"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG_FILE"
}

is_root_hash_name() {
  case "$1" in
    b74d2bd5.*|75680d2e.*|60a9fcc6.*|f468719d.*) return 0 ;;
  esac
  return 1
}

list_user_removed_dirs() {
  if [ -d /data/misc/user ]; then
    for d in /data/misc/user/*; do
      [ -d "$d" ] || continue
      echo "$d/cacerts-removed"
    done
  fi
  # Always include user 0 even if misc/user layout is odd
  echo "/data/misc/user/0/cacerts-removed"
}

list_removed_dirs() {
  echo "$KEYCHAIN_REMOVED"
  # Deduplicate without requiring awk
  _seen_keychain=1
  for _ud in $(list_user_removed_dirs); do
    [ "$_ud" = "$KEYCHAIN_REMOVED" ] && continue
    echo "$_ud"
  done
}

ensure_dir() {
  _d="$1"
  mkdir -p "$_d" 2>/dev/null
  chown system:system "$_d" 2>/dev/null || true
  chmod 775 "$_d" 2>/dev/null || chmod 771 "$_d" 2>/dev/null || true
  # Match typical keychain / user config labels
  restorecon -RF "$_d" 2>/dev/null \
    || chcon u:object_r:system_data_file:s0 "$_d" 2>/dev/null \
    || true
}

# Prefer the on-device system/APEX file (exact bytes + name). Else use bundled DER.
resolve_block_source() {
  _name="$1"
  _outvar="$2"
  _src=""

  if [ -f "$APEX_CERT_DIR/$_name" ]; then
    _src="$APEX_CERT_DIR/$_name"
  elif [ -f "$SYS_CERT_DIR/$_name" ]; then
    _src="$SYS_CERT_DIR/$_name"
  elif [ -f "$BLOCKLIST_DER_DIR/$_name" ]; then
    _src="$BLOCKLIST_DER_DIR/$_name"
  elif [ -f "$BLOCKLIST_DIR/$_name" ]; then
    _src="$BLOCKLIST_DIR/$_name"
  fi

  eval "$_outvar=\"\$_src\""
}

install_one_removed() {
  _src="$1"
  _dst_dir="$2"
  _name=${_src##*/}
  _dst="$_dst_dir/$_name"

  ensure_dir "$_dst_dir"

  # If source is PEM, convert to DER when openssl is available (KeyChain format).
  # CertificateFactory accepts PEM too, but DER matches Settings/KeyChain.
  if command -v openssl >/dev/null 2>&1; then
    if grep -q "BEGIN CERTIFICATE" "$_src" 2>/dev/null; then
      openssl x509 -in "$_src" -outform DER -out "$_dst" 2>/dev/null \
        || cp -f "$_src" "$_dst"
    else
      cp -f "$_src" "$_dst"
    fi
  else
    cp -f "$_src" "$_dst" 2>/dev/null || cat "$_src" >"$_dst"
  fi

  chown system:system "$_dst" 2>/dev/null || true
  chmod 644 "$_dst" 2>/dev/null
  restorecon "$_dst" 2>/dev/null \
    || chcon u:object_r:system_data_file:s0 "$_dst" 2>/dev/null \
    || true
}

install_blocklist() {
  _count=0
  _roots=0

  mkdir -p "$MARKER_DIR"
  rm -f "$MARKER_DIR"/*

  # 1) Disable every root hash that exists on the device (exact device file).
  for _hash in $ROOT_HASHES; do
    _idx=0
    while true; do
      _name="${_hash}.${_idx}"
      _src=""
      if [ -f "$APEX_CERT_DIR/$_name" ]; then
        _src="$APEX_CERT_DIR/$_name"
      elif [ -f "$SYS_CERT_DIR/$_name" ]; then
        _src="$SYS_CERT_DIR/$_name"
      else
        break
      fi
      echo "$_name" >"$MARKER_DIR/$_name"
      for _dir in $(list_removed_dirs); do
        install_one_removed "$_src" "$_dir"
        log "BLOCK root $_name (from device) -> $_dir/"
      done
      _count=$((_count + 1))
      _roots=$((_roots + 1))
      _idx=$((_idx + 1))
    done
  done

  # 2) Also install bundled blocklist (roots not on device + intermediates).
  #    Filename match helps SystemCertificateSource; content match helps TCS.
  if [ -d "$BLOCKLIST_DER_DIR" ] || [ -d "$BLOCKLIST_DIR" ]; then
    _bundled="$BLOCKLIST_DER_DIR"
    [ -d "$_bundled" ] && [ -n "$(ls -A "$_bundled" 2>/dev/null)" ] \
      || _bundled="$BLOCKLIST_DIR"
    for _src in "$_bundled"/*; do
      [ -f "$_src" ] || continue
      _name=${_src##*/}
      [ -f "$MARKER_DIR/$_name" ] && continue
      echo "$_name" >"$MARKER_DIR/$_name"
      for _dir in $(list_removed_dirs); do
        install_one_removed "$_src" "$_dir"
        log "BLOCK bundled $_name -> $_dir/"
      done
      _count=$((_count + 1))
    done
  fi

  log "cacerts-removed: $_count file(s), of which $_roots from on-device roots"
  return 0
}

uninstall_blocklist() {
  if [ -d "$MARKER_DIR" ]; then
    for _m in "$MARKER_DIR"/*; do
      [ -f "$_m" ] || continue
      _name=${_m##*/}
      for _dir in $(list_removed_dirs); do
        rm -f "$_dir/$_name"
        log "UNBLOCK $_name from $_dir/"
      done
      rm -f "$_m"
    done
  fi
  # Also wipe known bundled names
  for _dir in "$BLOCKLIST_DER_DIR" "$BLOCKLIST_DIR"; do
    [ -d "$_dir" ] || continue
    for _src in "$_dir"/*; do
      [ -f "$_src" ] || continue
      _name=${_src##*/}
      for _rd in $(list_removed_dirs); do
        rm -f "$_rd/$_name"
      done
    done
  done
}

notify_keychain() {
  am broadcast -a android.security.action.TRUST_STORE_CHANGED --receiver-include-background 2>/dev/null || true
  am broadcast -a android.security.STORAGE_CHANGED 2>/dev/null || true
  # Clear NetworkSecurityConfig cert cache in running apps is not possible;
  # zygote overlay below covers new processes.
}

fix_perms_dir() {
  _dir="$1"
  [ -d "$_dir" ] || return 0
  chown -R root:root "$_dir" 2>/dev/null
  chmod 755 "$_dir" 2>/dev/null
  if [ -n "$(ls -A "$_dir" 2>/dev/null)" ]; then
    chown root:root "$_dir"/* 2>/dev/null
    chmod 644 "$_dir"/* 2>/dev/null
  fi
  chcon -R u:object_r:system_security_cacerts_file:s0 "$_dir" 2>/dev/null \
    || chcon -R u:object_r:system_file:s0 "$_dir" 2>/dev/null \
    || true
}

# Build filtered CA dir: copy system/APEX certs, omit blocked root filenames.
build_filtered_store() {
  _src="$1"
  rm -rf "$WORK_DIR"
  mkdir -p "$WORK_DIR"
  if [ ! -d "$_src" ] || [ -z "$(ls -A "$_src" 2>/dev/null)" ]; then
    log "overlay: source empty $_src"
    return 1
  fi
  for _f in "$_src"/*; do
    [ -f "$_f" ] || continue
    _name=${_f##*/}
    if is_root_hash_name "$_name"; then
      log "overlay: omit $_name"
      continue
    fi
    cp -p "$_f" "$WORK_DIR/$_name" 2>/dev/null || cp "$_f" "$WORK_DIR/$_name"
  done
  fix_perms_dir "$WORK_DIR"
  log "overlay: built $WORK_DIR ($(ls "$WORK_DIR" 2>/dev/null | wc -l) certs)"
  return 0
}

# Magisk systemless: populate $MODDIR/system/etc/security/cacerts without roots
prepare_magisk_overlay() {
  _src=""
  if [ -d "$APEX_CERT_DIR" ] && [ -n "$(ls -A "$APEX_CERT_DIR" 2>/dev/null)" ]; then
    _src="$APEX_CERT_DIR"
  elif [ -d "$SYS_CERT_DIR" ] && [ -n "$(ls -A "$SYS_CERT_DIR" 2>/dev/null)" ]; then
    _src="$SYS_CERT_DIR"
  else
    return 1
  fi
  mkdir -p "$MODDIR$SYS_CERT_DIR"
  rm -rf "$MODDIR$SYS_CERT_DIR"
  mkdir -p "$MODDIR$SYS_CERT_DIR"
  for _f in "$_src"/*; do
    [ -f "$_f" ] || continue
    _name=${_f##*/}
    is_root_hash_name "$_name" && continue
    cp -p "$_f" "$MODDIR$SYS_CERT_DIR/$_name" 2>/dev/null || cp "$_f" "$MODDIR$SYS_CERT_DIR/$_name"
  done
  fix_perms_dir "$MODDIR$SYS_CERT_DIR"
  build_filtered_store "$_src"
  log "magisk overlay prepared from $_src"
}

bind_into_pid() {
  _pid="$1"
  _src="$2"
  _dst="$3"
  [ -n "$_pid" ] && [ -d "/proc/$_pid" ] || return 1
  if [ -x /system/bin/nsenter ]; then
    /system/bin/nsenter --mount=/proc/$_pid/ns/mnt -- \
      /bin/mount --bind "$_src" "$_dst" 2>/dev/null && return 0
    /system/bin/nsenter --mount=/proc/$_pid/ns/mnt -- \
      mount --bind "$_src" "$_dst" 2>/dev/null && return 0
  fi
  command -v nsenter >/dev/null 2>&1 || return 1
  nsenter --mount=/proc/$_pid/ns/mnt -- mount --bind "$_src" "$_dst" 2>/dev/null
}

inject_conscrypt_overlay() {
  [ -d "$APEX_CERT_DIR" ] || {
    log "no APEX cacerts; skip conscrypt inject"
    return 0
  }
  _bind="$WORK_DIR"
  if [ ! -d "$_bind" ] || [ -z "$(ls -A "$_bind" 2>/dev/null)" ]; then
    build_filtered_store "$APEX_CERT_DIR" || build_filtered_store "$SYS_CERT_DIR" || return 1
  fi

  # Also tmpfs-replace system path for non-APEX consumers
  if mount -t tmpfs -o mode=755 tmpfs "$SYS_CERT_DIR" 2>/dev/null \
    || mount -t tmpfs tmpfs "$SYS_CERT_DIR" 2>/dev/null; then
    cp -p "$_bind"/* "$SYS_CERT_DIR"/ 2>/dev/null || cp "$_bind"/* "$SYS_CERT_DIR"/
    fix_perms_dir "$SYS_CERT_DIR"
    log "tmpfs on $SYS_CERT_DIR"
    _bind="$SYS_CERT_DIR"
  fi

  for name in zygote zygote64; do
    for zp in $(pidof "$name" 2>/dev/null); do
      if bind_into_pid "$zp" "$_bind" "$APEX_CERT_DIR"; then
        log "bound APEX into $name $zp"
      else
        log "WARN: bind failed $name $zp"
      fi
      children=$(ps -o PID= -P "$zp" 2>/dev/null)
      [ -z "$children" ] && children=$(ps 2>/dev/null | awk -v P="$zp" '$3==P{print $2}')
      for pid in $children; do
        bind_into_pid "$pid" "$_bind" "$APEX_CERT_DIR" &
      done
      wait
    done
  done
}
