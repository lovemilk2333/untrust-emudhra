#!/system/bin/sh
# Shared helpers for Untrust eMudhra Compromised CAs
# POSIX sh (Magisk / KernelSU service scripts run under toybox/mksh)

MODDIR="${MODDIR:-${0%/*}}"
SYS_CERT_DIR=/system/etc/security/cacerts
APEX_CERT_DIR=/apex/com.android.conscrypt/cacerts
WORK_DIR="$MODDIR/cacerts-work"
LOG_FILE="$MODDIR/log.txt"

# Android OpenSSL subject_hash_old of roots that should no longer be trusted.
# b74d2bd5 = emSign ECC Root CA - G3 (cross-signer of compromised intermediates)
# 75680d2e = AAA Certificate Services / Comodo (Sectigo cross-sign root)
# 60a9fcc6 = emSign Root TLS CA - G3 (direct issuer; Microsoft root store)
# f468719d = emSign Root CS CA - G3 (code-signing root; Microsoft root store)
#
# SHA-256 fingerprints below are from:
#   https://emudhra.we-have-a-problem.com/impacted-intermediates.json
#   https://emudhra.we-have-a-problem.com/roots.json

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG_FILE"
}

# Compute cert SHA-256 fingerprint (uppercase hex, no colons). Empty on failure.
cert_sha256() {
  _f="$1"
  _out=""
  if command -v openssl >/dev/null 2>&1; then
    _out=$(openssl x509 -in "$_f" -noout -fingerprint -sha256 2>/dev/null)
    _out=$(echo "$_out" | sed 's/^.*=//' | tr -d ':' | tr 'a-f' 'A-F')
  fi
  echo "$_out"
}

# Match Android CA filename like b74d2bd5.0 / b74d2bd5.1
is_blocked_hash_name() {
  case "$1" in
    b74d2bd5.*|75680d2e.*|60a9fcc6.*|f468719d.*) return 0 ;;
  esac
  return 1
}

# Match known bad SHA-256 fingerprints (roots + compromised intermediates)
is_blocked_sha256() {
  case "$1" in
    # roots
    86A1ECBA089C4A8D3BBE2734C612BA341D813E043CF9E8A862CD5C57A36BBE6B) return 0 ;;
    D7A7A0FB5D7E2731D771E9484EBCDEF71D5F0C3E0A2948782BC83EE0EA699EF4) return 0 ;;
    7DD78D5F4F13459A83DFF9ABBBA62EDBAF6F2D102BF257FD712F4D9F2746ED8D) return 0 ;;
    F2EDAAFF3D9B701FB4D14C9F285F8C0BAD90FC3BCC1FA07D47F4718EDABA34A5) return 0 ;;
    # intermediates + cross-signs
    42C4ACCD12C4F59597925E1A08A7A90102608543809308D50EC427E118BA1493) return 0 ;;
    45A883F349AEDFD5F3A649B5498FFB121712BA8B448F3F2A91DBC5A766FCDDBE) return 0 ;;
    98B896625C0C230ADEEC3EB2CF6AAD5001ECF9156A68644E82374CE5833BC25B) return 0 ;;
    5F1DED4DD590AF74631290CF073B122A2AAC6A1FA479778A0BD43579BD832699) return 0 ;;
    E7568FE6E12331F4FD7DE61DA4C7559D0F8EB192A218D4741A3BA75184333838) return 0 ;;
    579480AEA166290BD3C643589E795FC0D0E54E86505D180F1DFF99EFD3199512) return 0 ;;
    0164D7CEAE5BB909C272AF151FF44B1177AE9B47D9424B94F1D9558C30934D19) return 0 ;;
    62B7F9868263F72F6911FC78CEAF72C1979158B7368BF648683BB2AA39B02E72) return 0 ;;
    CB6E15165AC802E9B3F993F16C25D41F4E81C21EBDE71AE1B012AC00BF9C7C3F) return 0 ;;
    7485B51C0ED192878FA1D2F948FB529AE1842CC5086C4B67F7BE5B2039DE9489) return 0 ;;
    432EC25F0D28DE9006D97BF752F17BBB2CD41F669933FCB072D9A1148D0261F3) return 0 ;;
    FD9D5C2DBBD4995AB69B8D50C439D9527B00529199C2FD01B2174EB58F07021F) return 0 ;;
    9E39DE2881273ACC225A149C72BA3E0F51424963669AB633EE1DC7DF5DB067B4) return 0 ;;
    A496E23AC0CAB8155FC9B117B97EAE368EFCBB9041AEC8804D5A308D2D01C2D8) return 0 ;;
    4B2460A466F95FD40113BCDCCA2CEB29B3B093921DE45474DA7DF48874C630B1) return 0 ;;
    84112972B8E59D14560AE7E7119654474AAD119990CF3722BFC1E3B91615E1FD) return 0 ;;
  esac
  return 1
}

# Remove blocked certs from a directory of Android CA files (*.0, *.1, ...)
remove_blocked_from_dir() {
  _dir="$1"
  _removed=0

  [ -d "$_dir" ] || return 0

  # Use find if available; else glob
  _list=""
  if command -v find >/dev/null 2>&1; then
    _list=$(find "$_dir" -maxdepth 1 -type f 2>/dev/null)
  else
    _list=$(ls "$_dir" 2>/dev/null)
  fi

  # shellcheck disable=SC2086
  for _entry in $_list; do
    # ls path may be basename only
    case "$_entry" in
      /*) _f="$_entry" ;;
      *)  _f="$_dir/$_entry" ;;
    esac
    [ -f "$_f" ] || continue
    _base=${_f##*/}

    if is_blocked_hash_name "$_base"; then
      log "REMOVE by hash-name: $_f"
      rm -f "$_f"
      _removed=$((_removed + 1))
      continue
    fi

    _fp=$(cert_sha256 "$_f")
    if is_blocked_sha256 "$_fp"; then
      log "REMOVE by sha256=$_fp: $_f"
      rm -f "$_f"
      _removed=$((_removed + 1))
    fi
  done

  log "Removed $_removed cert(s) from $_dir"
}

fix_perms() {
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

# Build a filtered CA directory in WORK_DIR from a source CA directory.
build_filtered_store() {
  _src="$1"

  rm -rf "$WORK_DIR"
  mkdir -p "$WORK_DIR"

  if [ ! -d "$_src" ] || [ -z "$(ls -A "$_src" 2>/dev/null)" ]; then
    log "Source CA dir empty or missing: $_src"
    return 1
  fi

  cp -p "$_src"/* "$WORK_DIR"/ 2>/dev/null || cp "$_src"/* "$WORK_DIR"/
  remove_blocked_from_dir "$WORK_DIR"
  fix_perms "$WORK_DIR"
  log "Built filtered store at $WORK_DIR ($(ls "$WORK_DIR" 2>/dev/null | wc -l) certs)"
  return 0
}

has_bind_mount() {
  _pid="$1"
  _target="$2"
  grep -q " ${_target} " "/proc/$_pid/mountinfo" 2>/dev/null
}

bind_into_pid() {
  _pid="$1"
  _src="$2"
  _dst="$3"
  [ -n "$_pid" ] || return 1
  [ -d "/proc/$_pid" ] || return 1
  if [ -x /system/bin/nsenter ]; then
    /system/bin/nsenter --mount=/proc/$_pid/ns/mnt -- \
      /bin/mount --bind "$_src" "$_dst" 2>/dev/null && return 0
    /system/bin/nsenter --mount=/proc/$_pid/ns/mnt -- \
      mount --bind "$_src" "$_dst" 2>/dev/null && return 0
  fi
  if command -v nsenter >/dev/null 2>&1; then
    nsenter --mount=/proc/$_pid/ns/mnt -- \
      mount --bind "$_src" "$_dst" 2>/dev/null && return 0
  fi
  return 1
}
