#!/usr/bin/env bash
#
# Take an upstream release without losing local features.
#
# The in-app updater cannot be used on a local build: it downloads upstream's
# .dmg and replaces the whole app bundle, which throws away every local commit
# AND changes the code signature. Same bundle ID with a different designated
# requirement means macOS treats it as a different app, so Accessibility and
# Microphone permissions are revoked and have to be granted again.
#
# This does it the other way round — merge upstream into the local branch, then
# rebuild and reinstall with the same signing identity, so the designated
# requirement is unchanged and the permissions survive.
#
# Usage:
#   scripts/update-from-upstream.sh --check       # report only, changes nothing
#   scripts/update-from-upstream.sh              # merge (if any), test, build, install
#   scripts/update-from-upstream.sh --reinstall   # rebuild and reinstall with no merge
#
# Signing config comes from the environment or an untracked .build-config, so
# nothing machine-specific is committed. See .build-config.example.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; }
die()  { fail "$*"; exit 1; }

MODE="merge"
case "${1:-}" in
  --check)     MODE="check" ;;
  --reinstall) MODE="reinstall" ;;
  "")          MODE="merge" ;;
  *)           die "unknown argument: $1 (expected --check, --reinstall, or nothing)" ;;
esac

# ---------------------------------------------------------------- signing config
# The environment wins over the file. Sourcing plain assignments would otherwise
# clobber an explicit override — which silently defeated a test of the signature
# gate below, since `CODESIGN_IDENTITY=… script` was ignored.
_env_app_name="${APP_NAME:-}"
_env_bundle_id="${BUNDLE_ID:-}"
_env_identity="${CODESIGN_IDENTITY:-}"
_env_install_path="${INSTALL_PATH:-}"
[ -f .build-config ] && . ./.build-config
APP_NAME="${_env_app_name:-${APP_NAME:-Megaphone}}"
BUNDLE_ID="${_env_bundle_id:-${BUNDLE_ID:-com.kuberwastaken.megaphone}}"
CODESIGN_IDENTITY="${_env_identity:-${CODESIGN_IDENTITY:-}}"
INSTALL_PATH="${_env_install_path:-${INSTALL_PATH:-/Applications/$APP_NAME.app}}"

# ---------------------------------------------------------------- 1. report state
bold "1. State"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1 \
  || die "no '$UPSTREAM_REMOTE' remote; add it with: git remote add upstream https://github.com/Kuberwastaken/megaphone.git"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
git fetch "$UPSTREAM_REMOTE" --quiet || die "git fetch $UPSTREAM_REMOTE failed"

UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-$UPSTREAM_REMOTE/main}"
BEHIND="$(git rev-list --count "HEAD..$UPSTREAM_BRANCH")"
AHEAD="$(git rev-list --count "$UPSTREAM_BRANCH..HEAD")"
ok "branch $BRANCH — $AHEAD local commit(s), $BEHIND new upstream commit(s)"

if [ "$BEHIND" != "0" ]; then
  echo
  git log --oneline "HEAD..$UPSTREAM_BRANCH" | sed 's/^/      /'
  echo
fi

INSTALLED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$INSTALL_PATH/Contents/Info.plist" 2>/dev/null || echo "not installed")"
ok "installed version: $INSTALLED_VERSION at $INSTALL_PATH"

if [ "$MODE" = "check" ]; then
  echo
  if [ "$BEHIND" = "0" ]; then
    bold "Up to date with $UPSTREAM_BRANCH. Nothing to merge."
  else
    bold "$BEHIND upstream commit(s) available. Re-run without --check to merge, test, build and install."
  fi
  exit 0
fi

# ---------------------------------------------------------------- 2. preflight
bold "2. Preflight"
[ -n "$CODESIGN_IDENTITY" ] \
  || die "CODESIGN_IDENTITY is not set. Copy .build-config.example to .build-config and fill it in.
      Two certs can share a name, which makes codesign fail 'ambiguous' — use the SHA-1 from:
      security find-identity -v -p codesigning"

if [ -n "$(git status --porcelain)" ]; then
  die "working tree is dirty. Commit or stash first — this script must be able to roll back cleanly."
fi
ok "working tree clean"

# The requirement the currently installed app is trusted under. Rebuilding must
# reproduce it exactly or the TCC grants are lost.
EXPECTED_DR=""
if [ -d "$INSTALL_PATH" ]; then
  EXPECTED_DR="$(codesign -d -r- "$INSTALL_PATH" 2>/dev/null | grep '^designated' || true)"
  [ -n "$EXPECTED_DR" ] && ok "recorded the installed app's designated requirement"
fi

SAVED_HEAD="$(git rev-parse HEAD)"
ok "rollback point: ${SAVED_HEAD:0:8}"

# ---------------------------------------------------------------- 3. merge
if [ "$MODE" = "merge" ] && [ "$BEHIND" != "0" ]; then
  bold "3. Merge $UPSTREAM_BRANCH"
  if ! git merge --no-edit "$UPSTREAM_BRANCH" >/dev/null 2>&1; then
    CONFLICTS="$(git diff --name-only --diff-filter=U)"
    git merge --abort 2>/dev/null || true
    fail "merge conflicts — aborted, tree restored. Resolve these deliberately:"
    echo "$CONFLICTS" | sed 's/^/      /'
    echo
    echo "      git merge $UPSTREAM_BRANCH    # then fix, make test, and re-run with --reinstall"
    exit 2
  fi
  ok "merged cleanly"
elif [ "$MODE" = "merge" ]; then
  bold "3. Merge"
  ok "nothing to merge — rebuilding current HEAD"
fi

# ---------------------------------------------------------------- 4. test
bold "4. Test"
if ! make test >/tmp/megaphone-update-test.log 2>&1; then
  tail -20 /tmp/megaphone-update-test.log | sed 's/^/      /'
  git reset --hard "$SAVED_HEAD" >/dev/null 2>&1
  die "tests failed — rolled back to ${SAVED_HEAD:0:8}. The installed app was not touched."
fi
ok "$(grep -c 'passed' /tmp/megaphone-update-test.log >/dev/null && echo 'MegaphoneTests passed')"

# ---------------------------------------------------------------- 5. build
bold "5. Build"
make clean >/dev/null 2>&1
if ! make all \
      APP_NAME="$APP_NAME" \
      BUNDLE_ID="$BUNDLE_ID" \
      CODESIGN_IDENTITY="$CODESIGN_IDENTITY" \
      >/tmp/megaphone-update-build.log 2>&1; then
  grep -E 'error:|ambiguous' /tmp/megaphone-update-build.log | head -10 | sed 's/^/      /'
  git reset --hard "$SAVED_HEAD" >/dev/null 2>&1
  die "build failed — rolled back to ${SAVED_HEAD:0:8}. The installed app was not touched."
fi
NEW_APP="build/$APP_NAME.app"
[ -d "$NEW_APP" ] || die "build reported success but $NEW_APP is missing"
ok "built $NEW_APP"

# ---------------------------------------------------------------- 6. signature gate
bold "6. Signature"
NEW_DR="$(codesign -d -r- "$NEW_APP" 2>/dev/null | grep '^designated' || true)"
[ -n "$NEW_DR" ] || die "the new build has no designated requirement — it was not signed"

if [ -n "$EXPECTED_DR" ] && [ "$NEW_DR" != "$EXPECTED_DR" ]; then
  fail "designated requirement CHANGED — installing this would revoke Accessibility and Microphone."
  echo "      installed: $EXPECTED_DR"
  echo "      new:       $NEW_DR"
  echo
  echo "      Fix CODESIGN_IDENTITY so it matches, or accept re-granting permissions"
  echo "      and install by hand. Nothing was replaced."
  exit 3
fi
ok "designated requirement unchanged — permissions will survive"
codesign --verify --strict "$NEW_APP" 2>/dev/null && ok "signature verifies"

# ---------------------------------------------------------------- 7. install
bold "7. Install"
if pgrep -x "$(echo "$APP_NAME" | tr -d ' ')Core" >/dev/null 2>&1; then
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 15); do
    pgrep -x "$(echo "$APP_NAME" | tr -d ' ')Core" >/dev/null 2>&1 || break
    sleep 0.4
  done
  ok "quit the running app"
fi

rm -rf "$INSTALL_PATH" && cp -R "$NEW_APP" "$INSTALL_PATH" || die "could not replace $INSTALL_PATH"
ok "installed to $INSTALL_PATH"

open -a "$INSTALL_PATH" || warn "could not relaunch — open it manually"
sleep 4
if pgrep -x "$(echo "$APP_NAME" | tr -d ' ')Core" >/dev/null 2>&1; then
  ok "running"
else
  warn "not running — check Console for a launch error"
fi

# ---------------------------------------------------------------- 8. summary
echo
bold "Done"
NOW_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$INSTALL_PATH/Contents/Info.plist" 2>/dev/null || echo '?')"
echo "  version $INSTALLED_VERSION -> $NOW_VERSION, $(git rev-list --count "$UPSTREAM_BRANCH..HEAD") local commit(s) preserved"
if [ "$(git rev-parse HEAD)" != "$SAVED_HEAD" ]; then
  echo "  merged upstream — not pushed. Push when you're happy:"
  echo "      git push origin $BRANCH"
fi
