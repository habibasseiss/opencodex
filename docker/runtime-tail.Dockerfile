

# Synology-friendly generic runtime stage.
# Keep the image independent from any deployment-specific UID/GID.
# Docker Compose can override USER at runtime.
FROM runtime AS runtime-generic-user

USER root

# An arbitrary runtime UID still needs to traverse the Bun home and app paths.
# State directories themselves remain writable through host bind-mount ownership.
RUN chmod 0755 \
      /home \
      /home/bun \
      /home/bun/app \
      /home/bun/.opencodex \
      /home/bun/.codex

# Bind-mounted state directories hide the config baked into the image, and Docker only seeds
# named volumes. Keep a copy outside the mounts and seed it on first start so the hub binds
# 0.0.0.0 inside the container.
RUN install -d -m 0755 /usr/local/share/opencodex \
 && install -m 0644 /home/bun/.opencodex/config.json /usr/local/share/opencodex/default-config.json

COPY --chmod=0755 <<'SCRIPT' /usr/local/bin/opencodex-entrypoint
#!/bin/sh
set -eu
config="${OPENCODEX_HOME:-/home/bun/.opencodex}/config.json"
if [ ! -e "$config" ]; then
  install -m 0600 /usr/local/share/opencodex/default-config.json "$config"
fi
exec /usr/local/bin/docker-entrypoint.sh "$@"
SCRIPT

USER bun

# Setting ENTRYPOINT clears the inherited CMD, so restate the upstream one.
ENTRYPOINT ["/usr/local/bin/opencodex-entrypoint"]
CMD ["bun", "run", "src/cli/index.ts", "start", "--port", "10100"]
