# Untrust eMudhra Compromised CAs

Magisk / KernelSU / APatch module that **blocks** the CAs from the [October 2026 eMudhra intermediate CA compromise](https://emudhra.we-have-a-problem.com/).

## Why v1.1 “blocked nothing”

Android does **not** treat files in `cacerts-removed` as a general SPKI blocklist.

| Mechanism | Path | How match works |
|---|---|---|
| KeyChain / TrustedCertificateStore | `/data/misc/keychain/cacerts-removed` | Exact certificate equality (KeyChain writes **DER**) |
| NetworkSecurityConfig / apps | `/data/misc/user/<id>/cacerts-removed` | **Filename** must equal the system CA file (`b74d2bd5.0`) |

Also: **compromised intermediates are not system trust anchors**. Putting them in `cacerts-removed` alone never breaks TLS. You must disable the **roots** that still sit in the system / Conscrypt store (`emSign ECC Root CA - G3`, `AAA Certificate Services`, …).

## What v1.2 does

1. **Disable (block)**  
   Copies the **on-device** root CA file (when present) into:
   - `/data/misc/keychain/cacerts-removed/`
   - `/data/misc/user/*/cacerts-removed/`  
   Prefers DER (KeyChain format). Bundled PEMs/DERs are fallbacks.

2. **Systemless overlay (effective TLS block)**  
   Builds a CA directory **without** the blocked root hashes and:
   - Magisk-mounts it over `/system/etc/security/cacerts`
   - Bind-mounts it into zygote/apps over `/apex/com.android.conscrypt/cacerts` (Android 14+)

The real system / APEX partition files are **not** deleted; they are hidden at runtime and marked disabled in Settings.

## Roots targeted

| Hash | Certificate |
|---|---|
| `b74d2bd5` | emSign ECC Root CA - G3 |
| `75680d2e` | AAA Certificate Services |
| `60a9fcc6` | emSign Root TLS CA - G3 |
| `f468719d` | emSign Root CS CA - G3 |

Bundled intermediate PEMs remain for completeness; TLS impact comes from the roots.

## Install

```bash
./build.sh
# flash dist/untrust-emudhra-v1.2.0.zip → reboot
```

Check:

```text
/data/adb/modules/untrust-emudhra/log.txt
```

You should see lines like `BLOCK root b74d2bd5.0 (from device)` and `bound APEX into zygote`.

Verify (expect certificate error):

```bash
curl -v https://dv-g3b-emudhra.we-have-a-problem.com/
curl -v https://dv-g3b-aaa-emudhra.we-have-a-problem.com/
```

Chrome may already block via CRLSet; use a client that uses the **system** CA store.

## Uninstall

Remove the module and reboot. `uninstall.sh` removes only this module’s `cacerts-removed` entries.

## License

[Unlicense](https://unlicense.org) — see [LICENSE](LICENSE).
