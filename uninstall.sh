#!/system/bin/sh
# Magisk calls this before removing the module. Nothing persistent outside MODDIR.
MODDIR=${0%/*}
rm -f "$MODDIR/log.txt"
rm -rf "$MODDIR/cacerts-work"
exit 0
