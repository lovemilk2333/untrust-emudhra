#!/system/bin/sh
# Runs during Magisk module installation (skipped by bare KSU bootstrap above).

SKIPUNMOUNT=false

ui_print ""
ui_print "******************************************"
ui_print " Untrust eMudhra Compromised CAs"
ui_print "******************************************"
ui_print ""
ui_print " Distrusts (Android subject_hash):"
ui_print "  b74d2bd5  emSign ECC Root CA - G3"
ui_print "  75680d2e  AAA Certificate Services"
ui_print "  60a9fcc6  emSign Root TLS CA - G3"
ui_print "  f468719d  emSign Root CS CA - G3"
ui_print ""
ui_print " Also strips matching intermediates by"
ui_print " SHA-256 if present in the CA directory."
ui_print ""
ui_print " Ref: https://emudhra.we-have-a-problem.com/"
ui_print ""
ui_print " Reboot required. Verify with:"
ui_print "  curl https://dv-g3b-emudhra.we-have-a-problem.com/"
ui_print " (certificate error = fixed)"
ui_print ""
