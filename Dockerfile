FROM caddy:2.8-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY bootstrap.sh index.html /srv/
EXPOSE 80
