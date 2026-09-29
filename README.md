# OpenCodex → GHCR builder

This repository is a small build wrapper for
[lidge-jun/opencodex](https://github.com/lidge-jun/opencodex). It does **not**
vendor or fork the OpenCodex source tree. GitHub Actions checks out the current
upstream `main` branch on every run, builds the upstream Dockerfile with
BuildKit, and publishes the result to GitHub Container Registry (GHCR).

## What it publishes

The workflow publishes an x86-64 image for:

- `linux/amd64`

QEMU is not used; the workflow builds only for the native x86-64 architecture of
GitHub's hosted Linux runner.

The image name is:

```text
ghcr.io/YOUR_GITHUB_USERNAME/opencodex
```

Each successful build publishes three tags:

```text
latest
<upstream package version>       # for example: 2.71.0
sha-<upstream commit>            # immutable-ish reference to the source snapshot
```

The workflow runs every day at **03:23 UTC**, can be started manually from the
Actions tab, and also runs when the workflow file itself is pushed to `main`.

## Setup

1. Create an empty GitHub repository. A public repository is simplest if you
   also want the GHCR image to be public.
2. Upload all files from this ZIP, including the hidden `.github` directory, and
   commit them to `main`.
3. In the repository, open **Settings → Secrets and variables → Actions →
   Variables** and create:
   - `OPENCODEX_UID` — for your NAS this is `1026`
   - `OPENCODEX_GID` — for your NAS this is `100`
4. Open **Actions → Publish OpenCodex image → Run workflow** for the first build
   (a push of the workflow file to `main` should also trigger it). The workflow
   fails early with a clear message if either variable is missing or
   non-numeric.
5. After the build succeeds, open your GitHub profile/organization's
   **Packages** section and select the `opencodex` package.
6. If you want your Synology to pull without authenticating, change the package
   visibility to **Public**.

No personal access token is required for the workflow itself. It publishes with
the repository's built-in `GITHUB_TOKEN`; the workflow grants only `contents:
read` and `packages: write`.

If your organization has restricted GitHub Actions or package permissions, an
administrator may need to allow the repository to publish packages.

## Synology Compose

Copy `compose.synology.example.yml` to your NAS, rename it if desired, and
replace:

```text
YOUR_GITHUB_USERNAME
```

with the lowercase GitHub user or organization that owns the package.

The published image adds a tiny Synology-specific final stage on top of the
upstream runtime. Its numeric UID and GID come from the GitHub repository
variables `OPENCODEX_UID` and `OPENCODEX_GID`. The stage makes `/home/bun` and
the application working directory traversable by that identity and keeps
OpenCodex's expected home paths. This avoids Bun's `CouldntReadCurrentDirectory`
failure when the runtime UID cannot traverse an ancestor directory.

The OpenCodex service stores its persistent data locally under:

```text
./opencodex-data/opencodex
./opencodex-data/codex
```

and listens on all NAS interfaces on port `10100`. With the example repository
variables above, the image runs OpenCodex as UID `1026`, GID `100`; Compose only
adds supplementary group `101` (`administrators`) for Synology ACL
compatibility. Do not add a separate `user:` override unless you intentionally
change the image's runtime identity.

Create the directories before the first start:

```bash
mkdir -p opencodex-data/opencodex opencodex-data/codex
sudo chown -R 1026:100 opencodex-data
```

If `opencodex-data` already exists from an earlier run, the `chown` is
important: OpenCodex creates lock/state files under `/home/bun/.opencodex`, and
UID `1026` must be able to write them.

Pull the image:

```bash
docker compose pull opencodex
```

On older Synology installations that use the standalone Compose command, use
`docker-compose` instead of `docker compose`.

### First-time OpenCodex token initialization

OpenCodex's Docker deployment expects a data-plane token in its persistent state
directory. Generate one, save it somewhere secure, and initialize the container
state once:

```bash
TOKEN="$(openssl rand -hex 32)"
printf '%s\n' "$TOKEN"
printf '%s\n' "$TOKEN" | docker compose run --rm -T opencodex \
  bun run docker/bootstrap-token.ts
```

Then start the services:

```bash
docker compose up -d
```

Because the example publishes OpenCodex on `0.0.0.0:10100`, restrict that port
with your NAS/firewall to the LAN, VPN, or other networks that should be able to
reach it.

## Updating the NAS

The GitHub workflow refreshes `latest` every day from upstream `main`. To deploy
the newest image on the Synology:

```bash
docker compose pull opencodex
docker compose up -d opencodex
```

Your `./opencodex-data` directories are bind mounts, so rebuilding/replacing the
container does not remove that state.

If the GHCR package is private, authenticate the NAS to GHCR before pulling. Use
a GitHub personal access token that can read packages rather than your GitHub
password:

```bash
printf '%s\n' "$GHCR_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

## Pinning or rolling back

Instead of `latest`, you can use the published upstream version tag:

```yaml
image: ghcr.io/YOUR_GITHUB_USERNAME/opencodex:2.71.0
```

or the source-commit tag shown in the package, for example:

```yaml
image: ghcr.io/YOUR_GITHUB_USERNAME/opencodex:sha-0123456789ab
```

The SHA tag is useful if a new upstream build causes a problem and you want to
return to a known source snapshot.

## Notes about scheduled workflows

GitHub runs scheduled workflows from the repository's default branch. GitHub may
automatically disable scheduled workflows in a **public** repository after 60
days with no repository activity. If that happens, re-enable the workflow from
the Actions tab or make a small commit to the repository.

## Upstream

OpenCodex is maintained at:

<https://github.com/lidge-jun/opencodex>

This builder does not change OpenCodex application code. During CI it appends a
small final Docker stage that accepts the repository-configured runtime UID/GID
as Docker build arguments, adjusts directory permissions for that identity, then
builds that target. OpenCodex is licensed under the MIT License. Review the
upstream project and provider terms before use.
