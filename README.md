# mac-bootstrap

Set up a clean Mac with one command:

```bash
curl -fsSL https://setup.jasielrivera.com | bash
```

It installs Apple's command line tools, Homebrew and the GitHub CLI, signs in to GitHub, clones the private setup repo and starts its guided setup (which asks what kind of Mac this is and explains each step).

This repo is public on purpose: the script contains no secrets. Everything sensitive needs a GitHub sign-in to the account that owns the private repo, and the infrastructure secrets need a separate identity on top of that.

Served by a tiny Caddy container (`Dockerfile`, `Caddyfile`). Changes to `bootstrap.sh` go live on the next deploy.
