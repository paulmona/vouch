# Vouch server image. Built from the top of the repository, where LICENSE and NOTICE
# are (docker build -t vouch-server -f server/Dockerfile .).
# Config at /etc/vouch/config.toml, data in /var/lib/vouch, sockets in /run/vouch.
FROM node:24.22.2-bookworm-slim@sha256:01d566e8d94d8c619591d78652babfccd3c6992a3dffa9ed5ab39e11cf6c70e9

ENV NODE_ENV=production
WORKDIR /opt/vouch
COPY server/package.json server/package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force
COPY server/src ./src
COPY server/migrations ./migrations
COPY LICENSE NOTICE ./

# A fixed uid/gid so host-side socket permissions can be planned for.
RUN groupadd --system --gid 10001 vouch \
 && useradd --system --uid 10001 --gid vouch --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin vouch \
 && install -d -m 0700 -o vouch -g vouch /var/lib/vouch \
 && install -d -m 0755 -o vouch -g vouch /run/vouch \
 && printf '#!/bin/sh\nexec node /opt/vouch/src/cli.ts "$@"\n' > /usr/local/bin/vouch && chmod 0755 /usr/local/bin/vouch

USER vouch
VOLUME ["/var/lib/vouch", "/run/vouch"]
EXPOSE 8770
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD node -e "fetch('http://127.0.0.1:8770/healthz').then(r=>process.exit(r.ok?0:1),()=>process.exit(1))"
CMD ["node", "/opt/vouch/src/main.ts", "--config", "/etc/vouch/config.toml"]
