FROM caddy:2.8-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY bootstrap.sh index.html og.png /srv/
EXPOSE 80
