# OpenCodex GHCR Builder

This repository builds the upstream `lidge-jun/opencodex` project every day and
publishes an amd64 Docker image to GitHub Container Registry (GHCR).

The published image is intentionally **independent of your Synology UID/GID**.
Runtime identity is selected by Docker Compose, so the same image can be used on
different hosts without rebuilding it.

## What the workflow does

Every day, on every push to `main`, and whenever you manually run the workflow,
GitHub Actions:

1. Checks out this repository.
2. Checks out the latest stable `lidge-jun/opencodex` release tag.
3. Stops here if an image for that upstream commit is already published (unless
   the manual run has **force** enabled).
4. Appends a tiny generic runtime stage to the upstream Dockerfile.
5. Builds only `linux/amd64` using BuildKit.
6. Publishes the image to:

   `ghcr.io/<your-github-username>/opencodex`

It publishes:

- `latest`
- the upstream release version
- `sha-<upstream-commit>`

No personal access token is needed for publishing from the workflow. It uses the
repository's built-in `GITHUB_TOKEN` with `packages: write`.

## GitHub setup

Create a GitHub repository and upload all files from this bundle, preserving the
`.github` directory.

Push to the default branch. Then open:

`Actions -> Publish OpenCodex image -> Run workflow`

After the first successful build, confirm that the package is visible in GitHub
Packages.

If your package is private, your Synology will need to authenticate to GHCR
before pulling it. If you make the package public, no registry login is needed
for pulling.

## Synology deployment

Copy:

- `compose.synology.example.yml` to your actual Compose project
- `.env.example` to `.env`

Edit the image name in Compose:

```yaml
image: ghcr.io/YOUR_GITHUB_USERNAME/opencodex:latest
```

The included `.env.example` contains the Synology account values used in the
example setup:

```dotenv
OPENCODEX_UID=1026
OPENCODEX_GID=100
OPENCODEX_EXTRA_GID=101
```

Docker Compose then applies them at runtime:

```yaml
user: "${OPENCODEX_UID}:${OPENCODEX_GID}"
group_add:
  - "${OPENCODEX_EXTRA_GID}"
```

The GitHub Actions workflow and image do not know or care about these IDs.

## Container network (IPv6)

The Compose example puts both services on a user-defined network that has IPv6
enabled:

```yaml
services:
  9router:
    networks:
      - agent-net
  opencodex:
    networks:
      - agent-net

networks:
  agent-net:
    enable_ipv6: true
    ipam:
      config:
        - subnet: fd00:5:5::/64
```

This is not decoration. Before binding, opencodex probes its configured port on
both loopback families (`127.0.0.1` and `::1`) to prove no other instance owns
this home. On a bridge network without IPv6 the `::1` connect fails as "network
unreachable" rather than "connection refused", which the probe cannot classify;
it fails closed and starts as a **sibling instance**. A sibling still answers
reads but refuses every management mutation that rewrites client state, so the
dashboard reports 409s such as `Mode switch failed (HTTP 409).`, and the Codex
device re-login fails for no visible reason. The startup log names the cause:

```text
A shared-client owner could not be verified (a managed client port answered but its listener
could not be classified); treating this instance as a sibling so Codex, Grok and Claude configs
are left alone.
```

The explicit ULA subnet is required because Docker only auto-assigns an IPv6
prefix when its default address pools contain one; Synology's Container Manager
configures IPv4-only pools, so `enable_ipv6: true` alone fails with `could not
find an available, non-overlapping IPv6 address pool among the defaults to
assign to the network`.

Verify after starting:

```bash
docker compose exec opencodex sh -lc 'cat /proc/net/if_inet6 >/dev/null && echo "IPv6 present" || echo "no IPv6"'
docker compose logs opencodex | grep -i sibling
```

`IPv6 present` and no sibling line mean the proxy started as the owner. A
loopback `openai_base_url` in the container's Codex config is what turns
opencodex's own port into a candidate in the first place; this network is what
keeps such a line harmless.

## Prepare local state directories

On the Synology:

```bash
mkdir -p opencodex-data/{opencodex,codex}
sudo chown -R 1026:100 opencodex-data
```

If you use different values in `.env`, use those values in `chown` instead.

## First-start configuration

The image contains a default hub config (`hostname: 0.0.0.0`, port `10100`).
Bind mounts hide files baked into an image, so on first start the entrypoint
copies that default to `opencodex-data/opencodex/config.json` when the file is
missing. An existing `config.json` is never overwritten.

The startup log always prints `http://localhost:10100`; that text is hard-coded
upstream and does not show the real bind address. Because the hub listens on
`0.0.0.0`, it refuses to start without the data-plane token created below.

## First-time OpenCodex token initialization

After pulling the image and before normal startup:

```bash
openssl rand -hex 32 | \
  docker compose run --rm -T opencodex \
  bun run docker/bootstrap-token.ts
```

Then:

```bash
docker compose up -d
```

## Sign in an OpenAI account (headless)

The container has no browser, so sign in with the device flow against the
ChatGPT/Codex account pool:

```bash
docker compose exec opencodex bun run src/cli/index.ts account login openai --device
```

Open the printed `https://auth.openai.com/codex/device` URL on any machine and
enter the code it shows. The account lands in `opencodex-data/opencodex`, so it
survives container rebuilds, and it appears on the dashboard's Codex Auth page,
where you select it as the active account and refresh its quota. The dashboard's
Add button drives the same flow.

The main card's **Re-login with device code** is a *re*-authentication of an
existing native `__main__` credential, not an enrollment. A fresh container has
none — `account main doctor` reports `authStatus: missing` — so that control
fails with `native_main_unavailable` ("enrollment is the native profile
workflow"). That is the proxy refusing an unsatisfiable request, not a broken
deployment; use the pool login above. If you also need the native slot populated
because some tool reads `$CODEX_HOME/auth.json` directly, copy a working
`auth.json` from a machine already signed into Codex to
`opencodex-data/codex/auth.json`, `chown 1026:100` and `chmod 600` it, then
recreate the container. ChatGPT refresh tokens rotate, so sign that source login
out afterwards.

## Dashboard access from the LAN

At `http://<nas-ip>:10100` the dashboard is a non-loopback (remote) bind, so it
keeps the admin token only in page memory: the browser asks for it again after
every reload, and the page's first data loads return 401 until you paste it.
Both are expected; a 401 from `opencodex-session` on a LAN address is by design,
because the loopback bootstrap does not mint a session when data-plane
authentication is required. Read the token from the container — the
`OPENCODEX_ADMIN_AUTH_TOKEN` environment value wins when it is set:

```bash
docker compose exec opencodex cat /home/bun/.opencodex/admin-api-token
```

Let the browser's password manager save it, or put the dashboard behind HTTPS
(for example Tailscale Serve) and pair the browser with `ocx gui pair`; pairing
over plain HTTP on a non-loopback origin is refused by design. This is the
management token, separate from the data-plane token created above, and it does
not belong in logs, screenshots, or issues.

## Updating OpenCodex on Synology

The GitHub workflow rebuilds `latest` daily from the latest upstream release.

To update the running NAS container:

```bash
docker compose pull opencodex
docker compose up -d opencodex
```

Your persistent data remains in:

```text
./opencodex-data/opencodex
./opencodex-data/codex
```

## Verify runtime identity

```bash
docker compose exec opencodex id
```

With the provided `.env`, it should run with UID `1026`, primary GID `100`, and
supplementary group `101`.

You can also inspect directory access with:

```bash
docker compose exec opencodex sh -c \
  'id; pwd; ls -ld / /home /home/bun /home/bun/app /home/bun/.opencodex /home/bun/.codex'
```

## Why the derived image changes permissions

The upstream image is designed around its built-in `bun` user. When Docker
Compose overrides the runtime UID, Bun still needs to traverse `/home/bun` and
`/home/bun/app`.

The derived final stage changes only directory traversal permissions. It does
not bake your NAS UID or GID into the image. Writable state comes from your bind
mounts, whose ownership is controlled on the Synology host.

## Architecture

This bundle intentionally builds only `linux/amd64`. No QEMU setup is needed.
