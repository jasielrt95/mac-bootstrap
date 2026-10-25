FROM caddy:2.8-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY bootstrap.sh /srv/bootstrap.sh
EXPOSE 80
