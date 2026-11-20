# atlas.germanium.cz – certificate renewal (UGREEN NAS)

The UGREEN DXP2800 (UGOS Pro, web UI <https://atlas.germanium.cz:9443>) uses a
Let's Encrypt certificate issued by cert-manager (DNS-01, ClusterIssuer
`letsencrypt-prod`):

| | |
|---|---|
| Certificate | `default/atlas` ([`../addons/certificate-atlas.yaml`](../addons/certificate-atlas.yaml)) |
| Secret | `default/atlas-tls` |
| Current cert | issued 2026-11-20, expires 2027-02-18 |

cert-manager renews the **Secret** automatically, but UGOS has no API or CLI for
importing certificates, so the **import into the NAS is manual** after every
renewal (roughly every 60 days).

## When

cert-manager renews ~30 days before expiry (next: around **2027-01-19**).
After that, import the new cert into UGOS before the old one expires.

Check the state:

```bash
kubectl get certificate atlas -n default -o wide
./export-atlas-cert.sh   # also tells you whether the NAS still serves an older cert
```

## Steps

1. Run the script from WSL:

   ```bash
   cd apps/cert-manager/atlas
   ./export-atlas-cert.sh
   ```

   It checks the Certificate is Ready, prints the expiry date and writes
   `atlas.fullchain.crt`, `atlas.crt`, `intermediate.crt` and `atlas.key` to
   the Windows Downloads folder (`DEST=/path` overrides the folder).
2. In UGOS: **Control Panel → Security → Certificate → Add → Import**.
   - Certificate: `atlas.crt` (or `atlas.fullchain.crt` if there's no intermediate field)
   - Private key: `atlas.key`
   - Intermediate certificate: `intermediate.crt` (if the field exists)
3. Set the new certificate as **default**, then delete the old one.
4. Delete `atlas.key` from Downloads.

## Verify

```bash
# Expiry and issuer of what the NAS serves
openssl s_client -connect atlas.germanium.cz:9443 -servername atlas.germanium.cz </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -serial

# Full chain: expect atlas -> YR1 -> Root YR -> ISRG Root X1, "Verify return code: 0 (ok)"
openssl s_client -connect atlas.germanium.cz:9443 -servername atlas.germanium.cz -showcerts </dev/null
```

The serial must match the one the script printed. Re-running the script should
report "NAS already serves this certificate".

## Gotcha: Chrome still shows "Not secure"

If Chrome keeps showing "Not secure" in the normal profile (incognito is fine),
it remembers the earlier "Proceed anyway" for the old self-signed cert:

1. `chrome://net-internals/#sockets` → **Flush socket pools**
2. Delete the site data for atlas.germanium.cz (padlock → Site settings → Delete data)
3. `chrome://restart`
