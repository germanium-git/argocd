# atlas.germanium.cz – certificate renewal (UGREEN NAS)

The UGREEN DXP2800 (UGOS Pro, web UI <https://atlas.germanium.cz:9443>) uses a
Let's Encrypt certificate issued by cert-manager (DNS-01, ClusterIssuer
`letsencrypt-prod`):

| | |
|---|---|
| Certificate | `default/atlas` ([`../addons/certificate-atlas.yaml`](../addons/certificate-atlas.yaml)) |
| Secret | `default/atlas-tls` |
| Current cert | issued 2026-11-20, expires 2027-02-18 |

cert-manager renews the **Secret** automatically. UGOS has no API for
certificates, so after every renewal (roughly every 60 days) the new cert has
to be pushed to the NAS: either with `export-atlas-cert.sh --upload` over SSH,
or by hand in the UGOS UI.

## When

cert-manager renews ~30 days before expiry (next: around **2027-01-19**).
After that, install the new cert on the NAS before the old one expires.

Check the state:

```bash
kubectl get certificate atlas -n default -o wide
./export-atlas-cert.sh   # also tells you whether the NAS still serves an older cert
```

## Option 1: upload over SSH (preferred)

```bash
cd apps/cert-manager/atlas
./export-atlas-cert.sh --upload
```

The script checks the Certificate is Ready, then pipes the cert and key over
`ssh atlas` into [`install-on-nas.sh`](install-on-nas.sh), which runs as root
on the NAS and:

1. validates the new cert (hostname, key match, not expired); exits without
   changes if the NAS already has it (`--force` reinstalls anyway),
2. backs up the current files to `/ugreen/.config/ssl-backup/<timestamp>/`
   (keeps the last 5),
3. replaces `/ugreen/.config/ssl/certs/atlas.germanium.cz/{cert.pem,privkey.pem}`
   (full chain + key; this is what nginx serves on 9443),
4. updates the expiry for atlas.germanium.cz in `/ugreen/.config/ssl/certcache.json`
   (what the UI's certificate list shows),
5. runs `nginx -t` and `systemctl reload nginx`, rolling back to the backup if
   either fails.

Finally it checks that port 9443 serves the new serial.

Requirements:

- `ssh atlas` works without a password: `~/.ssh/config` entry with
  `User petr` and `IdentityFile ~/.ssh/orangePiMac`, which is the key in
  `~petr/.ssh/authorized_keys` on the NAS. Override with `NAS_SSH=...`.
- `petr` has passwordless `sudo` on the NAS (`sudo -n` must work).
- The certificate must have been imported once via the UI, so that the
  `certs/atlas.germanium.cz` folder exists and `ssl.json` maps the web server to it.

The file layout is UGOS-internal and was checked on UGOS Pro (Debian 12) on
2026-11-20. After a firmware update, re-run the script: if the layout changed,
it stops before touching anything or fails the final serial check. In that
case, use option 2.

## Option 2: manual import in the UGOS UI

1. Run `./export-atlas-cert.sh` (no arguments). It writes `atlas.fullchain.crt`,
   `atlas.crt`, `intermediate.crt` and `atlas.key` to the Windows Downloads
   folder (`DEST=/path` overrides it).
2. UGOS: **Control Panel → Security → Certificate → Add → Import**.
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

The serial must match the one the script printed.

## Rollback

```bash
ssh atlas
sudo ls /ugreen/.config/ssl-backup/
sudo cp -a /ugreen/.config/ssl-backup/<timestamp>/{cert.pem,privkey.pem} /ugreen/.config/ssl/certs/atlas.germanium.cz/
sudo cp -a /ugreen/.config/ssl-backup/<timestamp>/certcache.json /ugreen/.config/ssl/
sudo nginx -t && sudo systemctl reload nginx
```

## Gotcha: Chrome still shows "Not secure"

If Chrome keeps showing "Not secure" in the normal profile (incognito is fine),
it remembers the earlier "Proceed anyway" for the old self-signed cert:

1. `chrome://net-internals/#sockets` → **Flush socket pools**
2. Delete the site data for atlas.germanium.cz (padlock → Site settings → Delete data)
3. `chrome://restart`
