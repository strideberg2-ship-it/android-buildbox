# devcontainer-notes — uncertainties, unverified claims, decisions to confirm

Drafted 2026-11-10. **No codespace was created, no image pulled, no real SDK downloaded.**
The two shell scripts *were* run against stubs on the phone (see "What I actually tested"
below — three real bugs came out of that). Treat every version number and every Codespaces
behaviour as a hypothesis to test on first `gh codespace create`.

## Unverified (marked `UNVERIFIED` in the files too)

1. **Base image tag** `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` — plausible but
   not confirmed against the registry. Fallback: `mcr.microsoft.com/devcontainers/base:ubuntu`.
2. **`ghcr.io/devcontainers/features/java:1` option names** — `version`, `jdkDistro`,
   `installGradle`, `gradleVersion`. If create fails, the feature's README is authoritative.
   Note: AGP normally wants JDK 17 or 21; 21 is a safe default for current AGP, 17 is the
   conservative choice. If Gradle complains about the JVM, this is the knob.
3. **Whether sshd is present** in `mcr.microsoft.com/devcontainers/base`. The Codespaces
   *default* image ships it; the plain base image may not. **This was the single most likely
   first-run failure** — symptom: `gh codespace ssh` refuses / port 22 closed. Currently
   pre-empted: `ghcr.io/devcontainers/features/sshd:1` is in `devcontainer.json`. If creation
   rejects that feature id, delete it and retry (the image already had sshd after all).
3b. **`"remoteUser": "vscode"`** was added so the container user does not depend on the base
   image's default. It must stay consistent with the `/home/vscode/...` paths in
   `containerEnv` — if you change one, change both.
4. **cmdline-tools URL** `commandlinetools-linux-11076708_latest.zip` — the hash segment
   moves with each release. Verify at developer.android.com/studio#command-tools.
5. **`SDK_PLATFORM=android-35` / `BUILD_TOOLS=35.0.0`** — must match whatever AGP the
   project uses. If Gradle says "failed to find target android-XX", change these two lines.
6. **`gh codespace cp` flags** (`-e`, `-c`, `remote:`) — I did not confirm the current
   syntax. Check `gh codespace cp --help` on the phone.
7. **`basicLinux32gb` machine type name** — believed correct for 2-core/8 GB/32 GB, not
   confirmed for the current `gh` version.
8. **Storage accounting**: that deleting a codespace stops the GB-month clock immediately.
   The whole delete-between-sessions strategy depends on it and it has not been measured.
9. **Creation log path** `/workspaces/.codespaces/.persistedshare/creation.log` — from
   memory of Codespaces layouts, not verified.
10. **`@devcontainers/cli` package name / `devcontainer up|exec` subcommands** — believed
    current, not verified.
11. **SDK disk footprint (10–15 GB)** — a vendor/community range, not one authoritative
    number. Measure with `du -sh ~/android-sdk ~/.gradle` after your first real build and
    adjust the README's advice.

## Decisions I made on your behalf — confirm or overrule

1. **Plain base image, not the Codespaces default `universal` image.** Universal is ~5 GB+
   and full of toolchains you don't use; storage is your binding quota. Cost: a cold SDK
   download (5–10 min) on every fresh codespace. **Acceptable?** If not, switch `image`
   and the SDK may already be preinstalled.
2. **`ANDROID_HOME` under `$HOME`, not `/opt`.** Avoids sudo, avoids permission bugs, and
   matches what a VPS/Docker setup does. Cost: it counts toward the Codespaces storage
   quota either way, so no real downside.
3. **No `platform-tools` / adb installed** (`INSTALL_PLATFORM_TOOLS=0`). You cannot use it
   anyway without wireless debugging, and it's dead weight. Flip to `1` only if a Gradle
   task demands it.
4. **Gradle wrapper preferred over a system Gradle.** bootstrap.sh installs a fallback
   Gradle *only* if there is no `./gradlew` and no system gradle. **Recommendation: commit
   the wrapper** (`gradle wrapper` once, or let Android Studio-less `gradle init` do it) —
   it pins the version per project and makes the box truly framework-agnostic.
5. **Only two VS Code extensions** (Java + Gradle). You work over SSH from Termux, so
   extensions are close to worthless here and cost storage. Delete the `customizations`
   block entirely if you never open the browser IDE.
6. **Backup is a whitelist, not a blacklist.** Anything not explicitly listed is not
   archived. Cost: if you later put something valuable in an unexpected place, it won't be
   backed up. Benefit: no chance of accidentally archiving a keystore. Confirm this is the
   trade you want.
7. **`backup.sh` refuses to run if it detects private-key patterns** in staged files. If
   that ever blocks a legitimate backup, the fix is to remove the file from the whitelist,
   not to weaken the check.
8. **No `.gitignore` entry for `.devcontainer/`** — the config is meant to be committed.
   Only `devcontainer.local.json` is ignored.

## What I actually tested (and what I did not)

Tested locally, in the Ubuntu proot environment on the phone, with stubs standing in for
`sdkmanager` and `curl`. No Android SDK was downloaded; no codespace, container or image
was created. So: **logic verified, real downloads not verified.**

- `bash -n` passes on both scripts (syntax).
- `bootstrap.sh`, fresh run: completes, exit 0, creates the expected
  `cmdline-tools/latest`, `platforms/android-35`, `build-tools/35.0.0`, `licenses/`, and
  appends exactly one `~/.bashrc` block.
- `bootstrap.sh`, second run: exit 0, skips cmdline-tools, does not duplicate the
  `~/.bashrc` block. Idempotency holds.
- `bootstrap.sh`, simulated 404 on the cmdline-tools download: exits 1 with
  "download failed. The pinned URL may be stale…" — loud failure confirmed.
- `backup.sh`: produces one tarball containing gitconfig, gradle.properties,
  local.properties, .vscode/, the bashrc marker block and MANIFEST.txt. `node_modules`
  inside a whitelisted dir is excluded. The manifest lists files correctly.
- `backup.sh` secret guard: planting a `-----BEGIN PRIVATE KEY-----` inside `.vscode/`
  aborts with "Refusing to create the archive" and writes nothing.
- `devcontainer.json`: parses cleanly as JSONC (comments stripped, then JSON-parsed).
  Key names and nesting are what the spec expects.

**Three real bugs found by testing, all fixed:**

1. `[[ cond ]] && cmd` under `set -e` aborts the script when the condition is false —
   `bootstrap.sh` would have died on the first line. Replaced with `if` blocks.
2. `yes | sdkmanager --licenses` **always** reported failure: `yes` gets SIGPIPE when
   sdkmanager exits, and `pipefail` propagates exit 141. Licence acceptance would have
   failed on every run, on every machine. Now runs with `pipefail` off for that one command.
3. `du -sh` on a missing directory exits non-zero, so the final summary step failed the
   whole script at the last line. Guarded with `|| true`.

These are the kind of thing that only shows up when you run the script, which is why the
drafts are marked unexecuted rather than finished — but the shell logic now has been run.

**Still purely hypothetical:** the actual SDK download, the devcontainer build, sshd
availability, all Codespaces CLI commands, the `gh codespace cp` syntax, and every storage
number.

## Risks

- **Codespaces free tier may simply be too tight** for a persistent Android toolchain.
  The honest position: 15 GB-month storage vs 10–15 GB of SDK. Delete-between-sessions
  works but means a 5–10 min cold start every time. If that becomes the dominant friction,
  GitHub Actions builds (push → artifact) are the better pattern, and a €5–10/mo VPS is
  the real fix — at which point storage stops mattering at all.
- **JDK/AGP/Gradle version triangle** is the classic first-build failure. If `assembleDebug`
  fails immediately with a JVM or "unsupported class file version" error, the JDK feature
  version is the culprit before anything else.
- **The install/test loop is the weakest link, not the build.** No adb, no logcat; a failed
  install shows as a toast you may miss. Build in a visible error surface (a crash screen
  that writes to a file, or an in-app log view) early, or debugging will be miserable.
- **Framework still undecided.** This box assumes Android APK output. If you land on
  React web/PWA, most of it is unnecessary; if you land on Expo with EAS Build, you may not
  need a codespace at all.
- **Framework-specific paths in the README** (`app/build/outputs/...`) assume a standard
  Gradle Android project. Flutter and RN differ; the README says so but the muscle memory
  may not.
