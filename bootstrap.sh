#!/bin/bash
# Bootstrap a clean Mac:
#
#   curl -fsSL https://setup.jasielrivera.com | bash
#
# Installs Apple's command line tools, Homebrew, Claude Code, Codex and the GitHub CLI, signs in to
# GitHub, clones the private mac-setup repo and starts its guided setup.
# Contains no secrets: everything sensitive needs your GitHub sign-in, and the
# infra secrets need your Infisical identity on top of that.
set -euo pipefail

SETUP_REPO="jasielrt95/mac-setup"
SETUP_DIR="$HOME/Developer/mac-setup"

bold() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; }

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

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# Runs a command; if it fails, asks to retry, skip (optional steps only) or quit.
# Returns 1 when an optional step is skipped.
attempt() { # attempt required|optional "what" command...
  local kind="$1" what="$2" choice
  shift 2
  while :; do
    "$@" && return 0
    fail "$what didn't work"
    if [ "$kind" = optional ]; then printf '  [r]etry, [s]kip, or [q]uit? [r] '; else printf '  [r]etry or [q]uit? [r] '; fi
    read -r choice <"$TTY" || choice=q
    case "${choice:-r}" in
      [Rr]*) bold "Retrying: $what" ;;
      [Ss]*) if [ "$kind" = optional ]; then return 1; fi ;;
      *) echo "  Stopped. Run the same command again to continue; finished parts are skipped."; exit 1 ;;
    esac
  done
}

install_homebrew() {
  local f rc=0
  f="$(mktemp -t brew-install)"
  curl -fsSL --retry 3 --connect-timeout 15 -o "$f" https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh || { rm -f "$f"; return 1; }
  /bin/bash "$f" <"$TTY" || rc=$?
  rm -f "$f"
  return "$rc"
}

# Through Software Update: works over SSH too (Apple's installer window doesn't).
# Returns 1 if Software Update doesn't offer the tools.
clt_install_from_software_update() {
  local flag=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress label
  echo "  Looking for the command line tools in Software Update (about a minute)"
  touch "$flag"
  label="$( { softwareupdate --list 2>/dev/null || true; } | sed -n 's/^[* ]*Label: \(Command Line Tools.*\)$/\1/p' | tail -1)"
  rm -f "$flag"
  [ -n "$label" ] || return 1
  echo "  Installing $label (asks for your Mac password)"
  attempt required "Installing $label" sudo softwareupdate --install "$label" --verbose <"$TTY"
}

clt_install_with_window() {
  xcode-select --install >/dev/null 2>&1 || true
  echo "  Click Install in the window that opens; waiting for it to finish (Ctrl-C to stop)"
  until xcode-select -p >/dev/null 2>&1 && [ -x /Library/Developer/CommandLineTools/usr/bin/clang ]; do sleep 10; printf '.'; done
  echo
}

unlock_keychain() { security unlock-keychain "$KEYCHAIN" <"$TTY" && security show-keychain-info "$KEYCHAIN" >/dev/null 2>&1; }

github_sign_in() { gh auth login --hostname github.com --git-protocol https --web <"$TTY" && gh auth status >/dev/null 2>&1; }

clone_setup_repo() {
  rm -rf "$SETUP_DIR" # leftovers of a failed clone
  gh repo clone "$SETUP_REPO" "$SETUP_DIR" -- --quiet
}

main() {
  [ "$(uname)" = Darwin ] || { echo "macOS only"; exit 1; }
  confirm_personal_use
  bold "Setting up this Mac ($(sw_vers -productName) $(sw_vers -productVersion), $(uname -m))"

  # 1. Apple's command line tools (git, compilers).
  if xcode-select -p >/dev/null 2>&1; then
    ok "Command line tools"
  else
    bold "Installing Apple's command line tools"
    clt_install_from_software_update || clt_install_with_window
    ok "Command line tools"
  fi

  # 2. Homebrew (asks for your password once).
  if [ -x /opt/homebrew/bin/brew ] || [ -x /usr/local/bin/brew ]; then
    ok "Homebrew"
  else
    bold "Installing Homebrew (it will ask for your Mac password)"
    attempt required "Installing Homebrew" install_homebrew
  fi
  if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; else eval "$(/usr/local/bin/brew shellenv)"; fi
  grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null || echo "eval \"\$($(command -v brew) shellenv)\"" >>"$HOME/.zprofile"

  # 3. Claude Code and Codex first, so a coding agent is on this Mac (for local or
  # remote sessions) even if a later step needs help. Casks: nothing to compile,
  # so this works even when the command line tools are outdated.
  local c
  for c in claude-code codex; do
    brew list --cask "$c" >/dev/null 2>&1 || { bold "Installing $c"; attempt optional "Installing $c" brew install --cask "$c" || true; }
  done
  ok "Claude Code $(claude --version 2>/dev/null | awk '{print $1}') and Codex $(codex --version 2>/dev/null | awk '{print $NF}')"

  # 4. After a macOS update the command line tools can be "too outdated" for
  # Homebrew, and installs fail. Homebrew's own check says so; Software Update
  # usually has the newer tools.
  # Captured first, NOT piped into `grep -q`: with pipefail, grep exiting early
  # made the check silently pass. Backup check: tools older than macOS itself.
  local report clt os outdated=0 reply
  report="$(brew doctor 2>&1 || true)"
  case "$report" in *"Command Line Tools are too outdated"*) outdated=1 ;; esac
  clt="$(pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null | awk '/^version:/{split($2,v,"."); print v[1]}' || true)"
  os="$(sw_vers -productVersion | cut -d. -f1)"
  if [ -n "$clt" ] && [ "$clt" -lt "$os" ]; then outdated=1; fi
  if [ "$outdated" = 1 ]; then
    bold "Updating Apple's command line tools (Homebrew says they're too outdated)"
    if ! clt_install_from_software_update; then
      echo "  Software Update doesn't offer an update. Homebrew's fix is to reinstall them:"
      echo "  remove /Library/Developer/CommandLineTools, then run Apple's installer again."
      echo "  (Homebrew can't install anything until this is done.)"
      printf '  Reinstall the command line tools now? [Y/n] '
      read -r reply <"$TTY" || reply=""
      case "${reply:-y}" in
        [Yy]*)
          # shellcheck disable=SC2024 # stdin from the terminal, for sudo's password prompt
          sudo rm -rf /Library/Developer/CommandLineTools <"$TTY"
          clt_install_from_software_update || clt_install_with_window ;;
        *) echo "  Skipped: installs will fail until the tools are updated (System Settings → General → Software Update, or https://developer.apple.com/download/all/)." ;;
      esac
    fi
  fi
  ok "Command line tools up to date"

  # 5. GitHub CLI + sign-in (shows a one-time code and opens the browser).
  command -v gh >/dev/null 2>&1 || { bold "Installing the GitHub CLI"; attempt required "Installing the GitHub CLI" brew install gh; }
  ok "GitHub CLI"
  # Over SSH the login Keychain is locked, and gh (which keeps its token there)
  # then looks signed out. Unlock it first.
  if ! security show-keychain-info "$KEYCHAIN" >/dev/null 2>&1; then
    bold "Unlocking the login Keychain (normal over SSH; asks for this Mac's password)"
    attempt required "Unlocking the Keychain" unlock_keychain
  fi
  if gh auth status >/dev/null 2>&1; then
    ok "Signed in to GitHub as $(gh api user --jq .login)"
  else
    bold "Sign in to GitHub"
    echo "  Copy the one-time code, press Enter to open the browser (over SSH: open"
    echo "  https://github.com/login/device on any device and enter the code)."
    attempt required "GitHub sign-in" github_sign_in
    ok "Signed in to GitHub as $(gh api user --jq .login)"
  fi
  attempt optional "Setting git to use gh for GitHub" gh auth setup-git || true

  # 6. The private setup repo.
  if [ -d "$SETUP_DIR/.git" ]; then
    if git -C "$SETUP_DIR" pull --ff-only --quiet; then ok "mac-setup up to date"; else
      fail "Couldn't update $SETUP_DIR (local changes?); using it as it is"
    fi
  else
    mkdir -p "$(dirname "$SETUP_DIR")"
    attempt required "Cloning $SETUP_REPO" clone_setup_repo
    ok "mac-setup cloned to $SETUP_DIR"
  fi

  if [ "${BOOTSTRAP_NO_RUN:-0}" = 1 ]; then ok "BOOTSTRAP_NO_RUN=1: stopping before the guided setup"; return; fi

  # 7. Guided setup.
  bold "Starting the guided setup"
  echo "  Stuck at any point? Open a new Terminal window and run: claude"
  exec "$SETUP_DIR/setup.sh" --guided <"$TTY"
}

# Wrapped in a function so a partial download can't run half a script.
main "$@"
