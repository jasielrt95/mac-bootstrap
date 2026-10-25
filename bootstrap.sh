#!/bin/bash
# Bootstrap a clean Mac:
#
#   curl -fsSL https://setup.jasielrivera.com | bash
#
# Installs Apple's command line tools, Homebrew and the GitHub CLI, signs in to
# GitHub, clones the private mac-setup repo and starts its guided setup.
# Contains no secrets: everything sensitive needs your GitHub sign-in, and the
# infra secrets need your Infisical identity on top of that.
set -euo pipefail

SETUP_REPO="jasielrt95/mac-setup"
SETUP_DIR="$HOME/Developer/mac-setup"

bold() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

# When run as `curl ... | bash`, stdin is the script itself; prompts must read
# from the terminal instead.
TTY="${BOOTSTRAP_TTY:-/dev/tty}"
[ -r "$TTY" ] || { echo "Run this in a Terminal window: curl -fsSL https://setup.jasielrivera.com | bash"; exit 1; }

confirm_personal_use() {
  printf '\n\033[1;33m%s\033[0m\n' "Read this first"
  cat <<'MSG'
  This is Jasiel Rivera's personal Mac setup. It is not a general-purpose tool.

  If you continue, it will install Apple's command line tools, Homebrew and the
  GitHub CLI, then ask you to sign in to GitHub and continue with a private
  setup that only works with Jasiel's own accounts.

  If this isn't your setup, stop here: nothing has been installed yet.
MSG
  local answer
  printf '\n  Type "yes" to continue (anything else stops): '
  read -r answer <"$TTY" || answer=""
  answer="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  if [ "$answer" != "yes" ]; then
    echo "  Stopped. Nothing was installed."
    exit 0
  fi
}

main() {
  [ "$(uname)" = Darwin ] || { echo "macOS only"; exit 1; }
  confirm_personal_use
  bold "Setting up this Mac ($(sw_vers -productName) $(sw_vers -productVersion), $(uname -m))"

  # 1. Apple's command line tools (git, compilers). The installer is a GUI dialog.
  if xcode-select -p >/dev/null 2>&1; then
    ok "Command line tools"
  else
    bold "Installing Apple's command line tools: click Install in the window that opens"
    xcode-select --install >/dev/null 2>&1 || true
    until xcode-select -p >/dev/null 2>&1; do sleep 10; printf '.'; done
    echo; ok "Command line tools"
  fi

  # 2. Homebrew (asks for your password once).
  if [ -x /opt/homebrew/bin/brew ] || [ -x /usr/local/bin/brew ]; then
    ok "Homebrew"
  else
    bold "Installing Homebrew (it will ask for your Mac password)"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" <"$TTY"
  fi
  if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; else eval "$(/usr/local/bin/brew shellenv)"; fi
  grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null || echo "eval \"\$($(command -v brew) shellenv)\"" >>"$HOME/.zprofile"

  # 3. GitHub CLI + sign-in (shows a one-time code and opens the browser).
  command -v gh >/dev/null 2>&1 || { bold "Installing the GitHub CLI"; brew install gh; }
  ok "GitHub CLI"
  if gh auth status >/dev/null 2>&1; then
    ok "Signed in to GitHub as $(gh api user --jq .login)"
  else
    bold "Sign in to GitHub"
    gh auth login --hostname github.com --git-protocol https --web <"$TTY"
  fi
  gh auth setup-git

  # 4. The private setup repo.
  if [ -d "$SETUP_DIR/.git" ]; then
    git -C "$SETUP_DIR" pull --ff-only --quiet && ok "mac-setup up to date"
  else
    mkdir -p "$(dirname "$SETUP_DIR")"
    gh repo clone "$SETUP_REPO" "$SETUP_DIR" -- --quiet && ok "mac-setup cloned to $SETUP_DIR"
  fi

  if [ "${BOOTSTRAP_NO_RUN:-0}" = 1 ]; then ok "BOOTSTRAP_NO_RUN=1: stopping before the guided setup"; return; fi

  # 5. Guided setup.
  bold "Starting the guided setup"
  exec "$SETUP_DIR/setup.sh" --guided <"$TTY"
}

# Wrapped in a function so a partial download can't run half a script.
main "$@"
