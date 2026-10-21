# Untrust eMudhra Compromised CAs

Magisk / KernelSU / APatch module that **distrusts** the certificate authorities involved in the **October 2026 eMudhra intermediate CA private-key compromise**.

Reference: [https://emudhra.we-have-a-problem.com/](https://emudhra.we-have-a-problem.com/)

Google / Android may already block the compromised intermediates via Play Services CRLSet-style updates. This module is a **local, system-wide workaround** for devices that still trust the affected roots (custom ROMs, delayed Mainline updates, non-Google builds, offline devices, apps using the system CA store without CT).

## What is removed from the trust store

| Android hash | Certificate |
|---|---|
| `b74d2bd5` | **emSign ECC Root CA - G3** (public root that signed the broken intermediates) |
| `75680d2e` | **AAA Certificate Services** (Comodo/Sectigo root used for cross-signs) |
| `60a9fcc6` | **emSign Root TLS CA - G3** (direct issuer root) |
| `f468719d` | **emSign Root CS CA - G3** (code-signing root) |

The module also drops any CA file whose SHA-256 fingerprint matches the eight compromised intermediates and their Sectigo cross-signs (from `impacted-intermediates.json`).

> **Side effect:** Legitimate certificates that still chain only through these roots will fail TLS. Chrome is removing `emSign ECC Root CA - G3` for the same reason. Prefer updated OS/browser trust stores when available.

## Compatibility

| Component | Support |
|---|---|
| Magisk | Yes (systemless mount + scripts) |
| KernelSU / APatch | Yes (`/data/adb/modules`) |
| Android ≤ 13 | `/system/etc/security/cacerts` overlay |
| Android 14+ | Conscrypt APEX bind-mount into zygote / apps (`service.sh`) |

## Install

1. Build the zip (see below) or use a release zip.
2. Flash in **Magisk / KernelSU / APatch** → Modules → Install from storage.
3. **Reboot**.
4. Optional check (certificate error means distrust worked):

```bash
# on device / via adb shell (if curl exists)
curl -v https://dv-g3b-emudhra.we-have-a-problem.com/
curl -v https://dv-g3b-aaa-emudhra.we-have-a-problem.com/
```

Or open those URLs in a browser that uses the **system** CA store (not a browser that already shipped its own blocklist).

Logs: `/data/adb/modules/untrust-emudhra/log.txt`

## Build zip

```bash
./build.sh
# → dist/untrust-emudhra-v1.0.0.zip
```

## Uninstall

Disable or remove the module in Magisk/KSU and reboot. Trust store returns to stock.

## Limitations

- Does **not** patch app-private CA bundles (e.g. some WebViews, custom OkHttp trust managers, bundled `cacert.pem`).
- Does **not** replace Google Play system updates; keep the device updated.
- Zygote bind-mount needs `nsenter` (present on modern Magisk/KSU environments). If inject fails, check `log.txt`.
- Removing **AAA Certificate Services** can break rare legacy chains that still use that root for non-eMudhra sites.

## License

MIT
