#!/usr/bin/env bash
# Lives at <repo>/scripts/bootstrap.sh  (chmod +x)
#
# Run MANUALLY, once per fresh codespace:
#     bash scripts/bootstrap.sh
#
# Why manual: this repo deliberately has no .devcontainer/, so Codespaces builds a
# container from its DEFAULT image, whose base storage GitHub does not bill. A
# devcontainer.json cannot be used to gain that - naming any image, even the stock
# universal one, makes the whole container billable. The cost is that there is no
# postCreateCommand any more, so this script is the one manual step. It is written
# to be idempotent (verified: re-running skips every step and exits 0), so running
# it again in the same box is harmless.
#
# Idempotent setup for the Android build box. Safe to re-run any number of times.
# Does: JDK check -> Android cmdline-tools -> SDK platform + build-tools -> licences
#       -> Gradle -> shell env.
# Does NOT: touch the network beyond Google/Maven downloads, read or write any secret,
#           install adb-dependent tooling, or run any git command.
#
# Usage:  bash .devcontainer/bootstrap.sh [ --force ]
#   --force  re-download cmdline-tools even if present

set -Eeuo pipefail

# ---------------------------------------------------------------- pinned versions
# UNVERIFIED as of 2026-11-10. If a download 404s, fix the URL from
# https://developer.android.com/studio#command-tools and the version list from
# `sdkmanager --list`. Keep the "-latest" naming Google uses for cmdline-tools.
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
SDK_PLATFORM="android-35"          # the platform your app compiles against
BUILD_TOOLS="35.0.0"               # must be >= what your AGP version asks for
GRADLE_VERSION="8.14"              # fallback only; a project's ./gradlew always wins

INSTALL_PLATFORM_TOOLS=0           # 0 = skip. adb is not part of our loop anyway
                                   # (no wireless debugging: banking-app conflict).
                                   # Set to 1 only if a Gradle task demands it.

# ---------------------------------------------------------------- paths / helpers
ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_HOME ANDROID_SDK_ROOT
SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
FORCE=0
# NB: use `if`, not `cond && cmd` — under `set -e` a false condition aborts the script.
if [[ "${1:-}" == "--force" ]]; then FORCE=1; fi

info() { printf '\n=== %s\n' "$*"; }
die()  { printf '\nFATAL: %s\n' "$*" >&2; exit 1; }

# Loud failure: say which line died, not just "exit 1".
trap 'printf "\nFATAL: bootstrap failed at line %s (command: %s)\nRe-run to resume; finished steps are skipped.\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# ---------------------------------------------------------------- 0. preflight
info "Preflight"
for cmd in curl unzip java; do
  command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' not found. JDK/curl/unzip should come from the devcontainer features; check the 'features' block in devcontainer.json."
done
AVAIL_MB=$(df -Pm "$HOME" | awk 'NR==2 {print $4}')
echo "free disk in \$HOME: ${AVAIL_MB} MB (a full SDK + Gradle cache needs ~10-15 GB)"
if [[ "$AVAIL_MB" -lt 4000 ]]; then
  echo "WARNING: less than 4 GB free - the SDK install will probably fail."
fi
java -version 2>&1 | sed 's/^/  /'

# ---------------------------------------------------------------- 1. cmdline-tools
info "Android cmdline-tools"
if [[ -x "$SDKMANAGER" && $FORCE -eq 0 ]]; then
  echo "already present, skipping: $SDKMANAGER"
else
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  tmpzip="$(mktemp -d)/cmdline-tools.zip"
  echo "downloading $CMDLINE_TOOLS_URL"
  curl -fSL --retry 3 -o "$tmpzip" "$CMDLINE_TOOLS_URL" \
    || die "download failed. The pinned URL may be stale - update CMDLINE_TOOLS_URL in this script."
  rm -rf "$ANDROID_HOME/cmdline-tools/latest"
  unzip -q "$tmpzip" -d "$ANDROID_HOME/cmdline-tools"
  # The zip unpacks to "cmdline-tools/", sdkmanager expects ".../cmdline-tools/latest/"
  mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  rm -rf "$(dirname "$tmpzip")"
  [[ -x "$SDKMANAGER" ]] || die "sdkmanager still missing after unpack - zip layout changed upstream."
fi

# ---------------------------------------------------------------- 2. licences
info "SDK licences"
mkdir -p "$ANDROID_HOME/licenses"
# Non-interactive accept. Harmless if already accepted. Output suppressed on purpose:
# it is ~30 screens of noise and contains nothing we need.
#
# pipefail has to be OFF for this one command: when sdkmanager exits, `yes` gets SIGPIPE
# and returns 141, which pipefail would report as a failure even though the licences were
# accepted. The `if` wrapper also keeps `set -e` from aborting on a legitimate failure,
# so we can report the real exit code. Verified against a stub: without this, every run fails.
set +o pipefail
if { yes | "$SDKMANAGER" --licenses; } >/dev/null 2>&1; then lic_rc=0; else lic_rc=$?; fi
set -o pipefail
[[ $lic_rc -eq 0 ]] || die "licence acceptance failed (exit $lic_rc) - run: $SDKMANAGER --licenses"
[[ -n "$(ls -A "$ANDROID_HOME/licenses")" ]] || die "licence files not created in $ANDROID_HOME/licenses"

# ---------------------------------------------------------------- 3. SDK packages
info "SDK platform + build-tools"
PKGS=("platforms;$SDK_PLATFORM" "build-tools;$BUILD_TOOLS")
if [[ $INSTALL_PLATFORM_TOOLS -eq 1 ]]; then PKGS+=("platform-tools"); fi

# sdkmanager is fast when everything is installed and only prints "already installed".
"$SDKMANAGER" --sdk_root="$ANDROID_HOME" "${PKGS[@]}" >/dev/null \
  || die "sdkmanager failed for: ${PKGS[*]}
Check the versions exist: $SDKMANAGER --list | grep -E 'platforms;|build-tools;'"

for pkg in "${PKGS[@]}"; do
  name="${pkg#*;}"; dir="${pkg%%;*}"
  [[ -d "$ANDROID_HOME/$dir/$name" ]] || die "expected $ANDROID_HOME/$dir/$name after install - not there."
done
echo "ok: ${PKGS[*]}"

# ---------------------------------------------------------------- 4. Gradle
info "Gradle"
if command -v gradle >/dev/null 2>&1; then
  echo "system gradle: $(gradle --version | awk '/^Gradle /{print $2}')"
elif [[ -x ./gradlew ]]; then
  echo "no system gradle, but ./gradlew exists - that is the preferred path, nothing to do"
else
  # Last resort so a brand-new empty repo is still usable. Projects should commit a wrapper.
  dest="$HOME/.local/gradle-$GRADLE_VERSION"
  if [[ -x "$dest/bin/gradle" ]]; then
    echo "fallback gradle already unpacked at $dest"
  else
    echo "downloading gradle $GRADLE_VERSION (fallback)"
    curl -fSL --retry 3 -o /tmp/gradle.zip \
      "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" \
      || die "gradle download failed. Check GRADLE_VERSION against https://gradle.org/releases/"
    mkdir -p "$HOME/.local"
    unzip -q /tmp/gradle.zip -d "$HOME/.local"
    rm -f /tmp/gradle.zip
  fi
  export PATH="$dest/bin:$PATH"
fi

# ---------------------------------------------------------------- 5. shell env
info "Shell environment"
# gh codespace ssh gives a non-login shell, so export here, once, with a marker block.
if ! grep -q 'android-buildbox:start' "$HOME/.bashrc" 2>/dev/null; then
  cat >>"$HOME/.bashrc" <<EOF
# android-buildbox:start
export ANDROID_HOME="$ANDROID_HOME"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$PATH"
# android-buildbox:end
EOF
  echo "added env block to ~/.bashrc"
else
  echo "env block already in ~/.bashrc"
fi
# shellcheck disable=SC1090
# Tolerant: a stock ~/.bashrc may reference unset vars; don't fail a good install on it.
source "$HOME/.bashrc" 2>/dev/null || echo "note: ~/.bashrc could not be sourced (harmless)"

# ---------------------------------------------------------------- 6. summary
info "Done"
# `du` on a missing dir exits non-zero, and pipefail would turn that into a failure of the
# whole script at the very last step. Hence `|| true`.
{ du -sh "$ANDROID_HOME" 2>/dev/null || true; } | sed 's/^/  SDK size:    /'
{ du -sh "$HOME/.gradle"  2>/dev/null || true; } | sed 's/^/  Gradle home: /'
cat <<'EOF'
Next (inside the repo):
  ./gradlew assembleDebug
  -> app/build/outputs/apk/debug/app-debug.apk

Remember: this SDK cache counts against the Codespaces storage quota.
Delete the codespace when you are done for the week (see README.md).
EOF
