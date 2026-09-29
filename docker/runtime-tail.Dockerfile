

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

USER bun
