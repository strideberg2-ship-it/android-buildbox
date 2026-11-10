#!/usr/bin/env bash
# DRAFT - copy to <repo>/scripts/backup.sh  (chmod +x)
#
# Archives the small amount of NON-Git state that is annoying to recreate, into ONE
# timestamped tarball. Everything else is either in Git or is a cache.
#
# Restore recipe:  git clone <repo> && bash .devcontainer/bootstrap.sh && tar -xzf <file> -C ~
# That is the whole point: backups carry preferences, not toolchains.
#
# WHAT IS BACKED UP (whitelist - nothing outside this list is touched)
#   ~/.gitconfig, ~/.bash_aliases, ~/.config/git/*      git identity + aliases
#   ~/.bashrc  (only the marked android-buildbox block)  env vars from bootstrap
#   ~/.gradle/gradle.properties                          build tuning (NOT ~/.gradle/caches)
#   <repo>/local.properties                              machine-specific SDK path
#   <repo>/.vscode/  <repo>/.devcontainer/*.local.json    per-machine workspace config
#   <repo>/notes/                                        your own notes, if you keep them there
#   a generated MANIFEST.txt                             what/when/versions, for forensics
#
# DELIBERATELY NOT BACKED UP
#   Android SDK, ~/.gradle/caches, ~/.m2, node_modules, .dart_tool, build/ and .gradle/
#     -> all reproducible from bootstrap.sh + one build; 10-15 GB of pointless bytes.
#   ~/.ssh, ~/.gnupg, any *.jks/*.keystore, google-services.json, .env with tokens
#     -> these must never leave their proper home. A git clone + CI secret supplies them
#        if/when release signing is actually needed. See the secret scan at the end.
#   Docker images, shell history, editor state.
#   Git itself: the repo remote IS the backup.
#
# Usage:  bash scripts/backup.sh [output-dir]      (default: ~/backups)

set -Eeuo pipefail

OUT_DIR="${1:-$HOME/backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="$OUT_DIR/buildbox-state-$STAMP.tar.gz"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"

die() { printf '\nFATAL: %s\n' "$*" >&2; exit 1; }
trap 'rm -rf "$STAGE"' EXIT
trap 'printf "\nFATAL: backup failed at line %s (command: %s)\nNo archive was written.\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# Files whose NAME suggests a secret are never archived, even if a whitelist entry
# happens to match. Cheap belt-and-braces.
SECRET_NAME_RE='(\.jks$|\.keystore$|keystore|google-services\.json|\.pem$|(^|/)\.env($|\.)|id_rsa|id_ed25519|\.p12$|\.pfx$)'

stage_file() {  # stage_file <abs-path> <archive-path>
  local src="$1" rel="$2"
  [[ -e "$src" ]] || return 0
  if printf '%s' "$src" | grep -Eqi "$SECRET_NAME_RE"; then
    echo "  SKIP (looks like a secret): $src"
    return 0
  fi
  mkdir -p "$STAGE/$(dirname "$rel")"
  cp -a "$src" "$STAGE/$rel"
  echo "  + $rel"
}

stage_dir() {   # stage_dir <abs-dir> <archive-prefix>
  local src="$1" prefix="$2"
  [[ -d "$src" ]] || return 0
  mkdir -p "$STAGE/$prefix"
  # --exclude keeps the usual junk out even if it sneaks into a whitelisted dir.
  rsync -a \
    --exclude='node_modules' --exclude='build' --exclude='.gradle' --exclude='.dart_tool' \
    --exclude='*.jks' --exclude='*.keystore' --exclude='google-services.json' \
    "$src/" "$STAGE/$prefix/" 2>/dev/null || cp -a "$src/." "$STAGE/$prefix/"
  echo "  + $prefix/"
}

echo "Staging non-Git state from $HOME and $REPO_ROOT"

stage_file "$HOME/.gitconfig"                "home/.gitconfig"
stage_file "$HOME/.bash_aliases"            "home/.bash_aliases"
stage_file "$HOME/.gradle/gradle.properties" "home/.gradle/gradle.properties"
stage_file "$REPO_ROOT/local.properties"    "repo/local.properties"
stage_file "$REPO_ROOT/.devcontainer/devcontainer.local.json" "repo/.devcontainer/devcontainer.local.json"

if [[ -d "$HOME/.config/git" ]]; then stage_dir "$HOME/.config/git" "home/.config/git"; fi
if [[ -d "$REPO_ROOT/.vscode" ]]; then stage_dir "$REPO_ROOT/.vscode" "repo/.vscode"; fi
if [[ -d "$REPO_ROOT/notes" ]]; then stage_dir "$REPO_ROOT/notes" "repo/notes"; fi

# ~/.bashrc: copy only the marker block that bootstrap.sh wrote. Not the whole file -
# a Codespaces ~/.bashrc is boilerplate, and pasting it into a VPS is a bad idea.
if [[ -f "$HOME/.bashrc" ]]; then
  block="$(awk '/android-buildbox:start/{f=1} f{print} /android-buildbox:end/{f=0}' "$HOME/.bashrc")"
  if [[ -n "$block" ]]; then
    mkdir -p "$STAGE/home"
    printf '%s\n' "$block" >"$STAGE/home/bashrc-buildbox-block"
    echo "  + home/bashrc-buildbox-block"
  fi
fi

# MANIFEST: dates and versions, so a future you can tell whether the archive is stale.
# The file list is computed BEFORE the manifest is written, so the manifest does not try to
# describe itself while being written (that produced a garbled listing in testing).
FILE_LIST="$(cd "$STAGE" && find . -type f | sed 's|^\./|  |' | sort)"
{
  echo "android-buildbox state backup"
  echo "created:  $(date -Is)"
  echo "host:     $(uname -srm)"
  echo "repo:     $REPO_ROOT"
  echo "git:      $(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo 'no git')"
  echo "java:     $(java -version 2>&1 | head -1 || echo 'absent')"
  echo "gradle:   $(gradle --version 2>/dev/null | awk '/^Gradle /{print $2}' || echo 'absent')"
  echo "sdk:      ${ANDROID_HOME:-unset}"
  echo "included:"
  printf '%s\n' "$FILE_LIST"
} >"$STAGE/MANIFEST.txt"
echo "  + MANIFEST.txt"

# Secret scan: refuse to ship a private key or a token pattern, whatever the file name.
if grep -rIlE 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|"type": *"service_account"' "$STAGE" 2>/dev/null | grep -q .; then
  echo "Files that look like they contain secrets:" >&2
  grep -rIlE 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|"type": *"service_account"' "$STAGE" 2>/dev/null | sed 's|^|  |' >&2
  die "Refusing to create the archive. Remove those files from the whitelist, or exclude them."
fi

mkdir -p "$OUT_DIR"
tar -czf "$ARCHIVE" -C "$STAGE" .
chmod 600 "$ARCHIVE"

echo
echo "Wrote $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"
echo "Move it OFF the box (scp from Termux, or push to a private repo you own)."
echo "Restore:  git clone <repo> && bash .devcontainer/bootstrap.sh && tar -xzf $(basename "$ARCHIVE") -C ~"