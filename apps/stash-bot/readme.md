# Stash Bot (Hermes Agent + Slack + Google Sheets + Notion)

A chat assistant for the scale-modelling stash. You ask in Slack ("do I have a 1/48 MiG-21 ejection seat?",
"what paints am I missing for the MiG-21R project?", "bought Mr.Color C36 for the Su-25, add it") and the
bot answers from, and writes to, your existing records:

| Data | Where | Bot access |
|---|---|---|
| Kits, accessories, paints | Google Sheet **Aircraft Kits** (`1JuRrPEz8kAJzVHe5wVWKhvONaG8NNbg3jJ58WUjwDu0`), tabs *Aircraft Kits*, *Accessories*, *Paints* | read + append/update rows |
| Projects | Notion pages under **Home / Plastic Modeling** (e.g. *MiG-21R - Czech 1994*) | read + update pages |

```
Slack (Socket Mode, outbound only)
  └─ pod stash-bot
       ├─ hermes      nousresearch/hermes-agent  (LLM: Claude via ANTHROPIC_API_KEY)
       ├─ sheets-mcp  uvx mcp-google-sheets on 127.0.0.1:8001 (Google service account)
       └─ notion-mcp  mcp/notion on 127.0.0.1:3000 (bearer MCP_AUTH_TOKEN)
```

## Layout

- `config/config.yaml`: Hermes config (model, Slack behaviour, disabled toolsets, MCP servers).
  The init container renders it into `/opt/data/config.yaml` on every start, substituting
  `__MCP_AUTH_TOKEN__`. Git is the source of truth, so changes made in the pod are lost on restart.
- `config/SOUL.md`: the bot's persona, the sheet/page layout it works with, and its rules (search before
  adding, confirm before writing, never delete). Copied to `/opt/data/SOUL.md`. **If you add or rename
  sheet columns, update this file.**
- Both files go through `configMapGenerator` with a hash suffix, so editing them rolls the pod.
- `pvc.yaml`: `/opt/data` on `nfs-atlas` (sessions, memories, learned skills, logs).
- `networkpolicy.yaml`: no ingress; egress limited to DNS and public 443. **Flannel does not enforce
  NetworkPolicy**, so for now this only documents intent.
- Tool allow-lists:
  - Sheets: `ENABLED_TOOLS` in `deployment.yaml`. Read, find, append and update are allowed; share, copy,
    delete and new-spreadsheet calls are not.
  - Notion: `tools.include` in `config.yaml` (search/read/create/update page; no delete).
  - Hermes shell, browser and code-execution toolsets are disabled.
- The Sheets sidecar runs `uvx --with "mcp<2" mcp-google-sheets@0.6.3` and downloads the packages from PyPI at
  startup (`mcp<2`: 0.6.3 imports `mcp.server.fastmcp`, renamed in mcp 2.x).
- Both MCP servers are native sidecars (`initContainers` with `restartPolicy: Always` + `startupProbe`), so the
  `hermes` container starts only once they listen. Otherwise Hermes "parks" an unreachable MCP server.
- Rotate a single key without touching the others:
  `kubectl create secret generic stash-bot-secrets -n stash-bot --from-file=KEY=<file> --dry-run=client -o json | kubeseal --merge-into stash-bot-sealedsecret.yaml`
  (it rewrites the file as JSON; convert back to YAML).

## One-time setup

1. **Paints tab**: the paint inventory is currently a CSV (`Gunze Mr. Color Paint Inventory.csv`), and the
   Sheets API cannot edit CSV files. Open *Aircraft Kits* → File → Import → choose the CSV → **Insert new
   sheet(s)**, then rename the tab to `Paints`. Keep the columns: `Code, Name, Standard (FS/BS/RLM), Quantity, Kit`.
2. **Google service account**: in Google Cloud Console, create (or pick) a project, enable the **Google Sheets
   API** and **Google Drive API**, and create a service account with a JSON key. Share the *Aircraft Kits*
   spreadsheet (only that file) with the service account e-mail as **Editor**.
3. **Notion integration**: https://www.notion.so/profile/integrations → New internal integration
   "Stash Bot" (capabilities: read, update, insert content). Copy the `ntn_…` token. On the
   **Plastic Modeling** page choose `⋯ → Connections → Stash Bot`.
4. **Slack app**: create it from a manifest (or generate one with
   `kubectl exec -n stash-bot deploy/stash-bot -c hermes -- hermes slack manifest --agent-view`).
   - Enable Socket Mode and create an app-level token (`xapp-…`) with `connections:write`.
   - Bot scopes: `chat:write app_mentions:read channels:history channels:read groups:history im:history
     im:read im:write mpim:history mpim:read users:read files:read files:write reactions:read`
   - Bot events: `message.im message.mpim message.channels message.groups app_mention`
   - App Home: enable the Messages tab. Install the app, copy the bot token (`xoxb-…`).
   - Find your Member ID (profile → ⋯ → Copy member ID) for `SLACK_ALLOWED_USERS`.
   - `/invite @Stash Bot` in `#modelling` (in channels it needs an @mention; DMs work without one).
5. **Anthropic API key** from https://console.anthropic.com.
6. **Seal the secret** (run from this directory):
   ```bash
   kubectl create secret generic stash-bot-secrets -n stash-bot \
     --from-literal=SLACK_BOT_TOKEN=xoxb-... \
     --from-literal=SLACK_APP_TOKEN=xapp-... \
     --from-literal=SLACK_ALLOWED_USERS=U0XXXXXXX \
     --from-literal=ANTHROPIC_API_KEY=sk-ant-... \
     --from-literal=NOTION_TOKEN=ntn_... \
     --from-literal=MCP_AUTH_TOKEN="$(openssl rand -hex 32)" \
     --from-literal=GOOGLE_SA_JSON_B64="$(base64 -w0 stash-bot-sa.json)" \
     --dry-run=client -o yaml | kubeseal --format yaml > stash-bot-sealedsecret.yaml
   shred -u stash-bot-sa.json
   ```
7. Commit, merge, then `kubectl apply -f apps/stash-bot/application.yaml`.

## Operate

```bash
kubectl logs -n stash-bot deploy/stash-bot -c hermes -f          # gateway / Slack connection
kubectl logs -n stash-bot deploy/stash-bot -c sheets-mcp          # Google Sheets MCP
kubectl logs -n stash-bot deploy/stash-bot -c notion-mcp          # Notion MCP
kubectl exec -n stash-bot deploy/stash-bot -c hermes -- hermes tools   # verify toolsets / MCP tools
kubectl exec -n stash-bot deploy/stash-bot -c hermes -- hermes config get model --json
```

Change the model in `config/config.yaml` (`model.default`; for example `claude-haiku-5-5` is cheaper).

## Smoke test

1. "Do I have anything for the MiG-21SMT?" → kit 8233 plus CIRO canopy C-453 and Quickboost seat QB48507.
2. "Do I have FS 36375?" → C308 Gray, reserved for F-16I Sufa.
3. "Add Mr.Color C36, 1 bottle" → confirmation → a new row at the end of *Paints*.
4. Repeat 3 → the bot offers to raise `Quantity` instead of adding a duplicate.
5. "What do I need for MiG-21R - Czech 1994?" → reads the Notion Colors table (C66, C42, C43, C65, C302,
   MC213, MC214, SM201…) → ✅ / ♻️ equivalent / 🛒 missing.

## Roadmap (same pod, extra `mcp_servers` entries)

- Phase 2: Home Assistant MCP (ESPHome devices), Prometheus MCP → kube-prometheus-stack (uplink status
  from telegraf), n8n MCP Server Trigger (workflows as tools, weekly "low paint" digest).
- Phase 3: Paperless-ngx MCP (read-only token) for invoice search.

Notion's local MCP server (`mcp/notion`) is in maintenance mode; Notion now supports only the remote OAuth
server (`https://mcp.notion.com/mcp`). Hermes supports that one too (`auth: oauth` + `hermes mcp login notion`)
if the local one stops working.
