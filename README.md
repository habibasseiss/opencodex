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
3. Appends a tiny generic runtime stage to the upstream Dockerfile.
4. Builds only `linux/amd64` using BuildKit.
5. Publishes the image to:

   `ghcr.io/<your-github-username>/opencodex`

It publishes:

- `latest`
- the upstream release version (a re-run without a new release overwrites this
  tag)
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

## Prepare local state directories

On the Synology:

```bash
mkdir -p opencodex-data/{opencodex,codex}
sudo chown -R 1026:100 opencodex-data
```

If you use different values in `.env`, use those values in `chown` instead.

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
