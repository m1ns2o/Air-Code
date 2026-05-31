# Air Code Server Deployment

This is the practical server-side deployment path for a remote machine that will
host the real filesystem, git repository, terminal, LSP processes, and agent
CLIs.

## Recommended Flow

From the Air Code repository:

```sh
./scripts/install_aircoded_server.sh --service --yes
```

Defaults:

- Installs the backend binary to `~/.aircode/bin/aircoded`
- Generates or copies config at `~/.aircode/etc/config.json`
- Uses `~/.aircode/workspaces` as the default workspace root when no config is supplied
- Installs/checks `ripgrep`
- Configures `codex`, `claude`, and `hermes`
- Configures language intelligence for TypeScript/JavaScript/React, Python, and Vue
- Writes a launchd user service on macOS or a systemd user service on Linux when `--service` is passed
- Enables Codex Goals by writing `features.goals = true` to `CODEX_HOME/config.toml` or `~/.codex/config.toml`

To copy an existing config:

```sh
./scripts/install_aircoded_server.sh --config backend/config.json --service --yes
```

To generate a deployment config for a specific workspace root:

```sh
./scripts/install_aircoded_server.sh \
  --workspace-root /srv/aircode/workspaces \
  --addr 127.0.0.1:8080 \
  --service \
  --yes
```

## Start And Stop

macOS:

```sh
launchctl load ~/Library/LaunchAgents/com.aircode.aircoded.plist
launchctl unload ~/Library/LaunchAgents/com.aircode.aircoded.plist
```

Linux:

```sh
systemctl --user daemon-reload
systemctl --user enable --now aircoded
systemctl --user disable --now aircoded
```

## Reverse Proxy

Air Code expects the Go server to sit behind your own HTTPS reverse proxy for
public access. Keep `aircoded` bound to `127.0.0.1:8080` unless you intentionally
expose it on a private network.

Minimum proxy requirements:

- Forward `/v1/*` HTTP requests
- Forward WebSocket upgrade requests for events, terminal streams, and LSP streams
- Preserve the `Authorization: Bearer <token>` header
- Terminate TLS at the proxy

## Post-Install Checks

```sh
~/.aircode/bin/aircoded doctor -config ~/.aircode/etc/config.json
curl http://127.0.0.1:8080/health
```

Authenticated check:

```sh
TOKEN="$(jq -r .authToken ~/.aircode/etc/config.json)"
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8080/v1/workspace-roots
```

Codex Goals check:

```sh
grep -A3 '^\[features\]' "${CODEX_HOME:-$HOME/.codex}/config.toml"
```

Expected:

```toml
[features]
goals = true
```

If Codex was already running, restart the Codex CLI/session so it reloads the
updated config.
