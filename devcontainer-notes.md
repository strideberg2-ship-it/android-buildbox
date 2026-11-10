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

- **Codespaces free tier: the SDK was never the problem.** Measured 2026-11-10 — the whole
  SDK is **437 MB**, not the 10–15 GB this note originally claimed. The binding cost is the
  *container image*: a custom `image:` billed ~16 GB of loop storage, more than the entire
  15 GB-month quota. See the experiment result at the end of this file. This risk is
  downgraded from "free tier may be too tight" to "keep the container free and the SDK is
  irrelevant".
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


---

# RESULTS 2026-11-10 — first codespace created, everything tested for real

Supersedes the "no codespace was created, no image pulled" caveat at the top of this file.

## Verified on first create (all six former UNVERIFIED items passed)

Created `basicLinux32gb` in WestEurope from the `image:`-based config:

- Base image `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` → `Ubuntu 24.04.3 LTS`.
- `ghcr.io/devcontainers/features/java:1` with `version: 21`, `jdkDistro: ms`,
  `installGradle: true`, `gradleVersion: 8.14` → **all four option names correct**;
  JDK `21.0.13.0.2` (Microsoft), Gradle `8.14.6` at `/usr/local/sdkman/candidates/gradle/current`.
- `github-cli:1` → `/usr/bin/gh`. `sshd:1` → `/usr/sbin/sshd` + host keys.
- `postCreateCommand` ran `bootstrap.sh` to completion: cmdline-tools `11076708_latest`
  unpacked to `cmdline-tools/latest/bin/`, 8 licence files written, `platforms/android-35`,
  `build-tools/35.0.0`, `.bashrc` marker block added exactly once.
- **Idempotency proven**: re-ran `bootstrap.sh` in the live box — every step skipped,
  `EXIT=0`, no duplicate `.bashrc` block, SDK still 437 MB.

## Measured sizes (this retires the "10–15 GB" estimate)

| Path | Size |
|---|---|
| `~/android-sdk` | **437 MB** |
| — cmdline-tools / build-tools / platforms / licences | 148 / 147 / 142 / 0.04 MB |
| `~/.gradle` (before any build) | 252 KB |
| `/usr/local/sdkman` | 500 MB |
| `/usr` | 1.2 GB |

Loop device with the custom image: `/dev/loop4` **16 GB used of 32 GB** while `/workspaces`
held only 788 KB — the image itself dominates. `df -h /` said 14 GB avail while
`bootstrap.sh`'s own preflight `df -Pm $HOME` said 28.7 GB; the two disagree and 14 GB is
the conservative number.

## The default-image experiment — NEGATIVE RESULT, do not repeat blindly

Hypothesis: omitting `image:` entirely makes Codespaces fall back to its default image,
whose base container storage GitHub documents as free, so ~16 GB of billed storage would
disappear while the features still supply JDK/Gradle.

**What actually happened** (branch `default-image`, commit `a674286`, one real create):

- `devcontainer-info` reported: `Definition ID: base-alpine`, `Variant: 3.23`,
  `Image version: 4.0.9`. That is **Alpine**, *not* the documented `universal` image.
- Inside the box: `sh`/`bash` and `git` present; `curl`, `unzip`, `python3`, `code` present;
  **`java` MISSING, `gh` MISSING, `node` MISSING**. `/etc/os-release` → Alpine Linux 3.23.8.
- `$HOME/android-sdk` did **not exist** — `bootstrap.sh` could not have run (no bash at
  postCreate time, no java/gh for its preflight), so the box was unusable as a build box.
- Disk did drop dramatically: `/` and `/workspaces` both **811 MB used, 29 GB avail** —
  versus 16 GB with the custom image. So the storage theory was right; the *content* was wrong.

**Conclusion: the free storage is real, but the `image:` fallback is not `universal`.** Two
things were conflated and this experiment separates them:

1. *Free container storage* comes from using GitHub's **default image**.
2. The **documented `universal` image** is only what you get when there is **no
   `devcontainer.json` at all** — and it is billed like any other custom image if you name it.

So you cannot get "universal image + free storage" from a repo that has a devcontainer config.
The honest options are:

- **(A) Custom image** (`ubuntu-24.04`): correct toolchain, all features work, but ~16 GB of
  billed storage — a single codespace exceeds the whole 15 GB-month free quota.
- **(B) No devcontainer config at all**: get the free `universal` image with Java/Node/gh
  preinstalled, but you lose `features`, `postCreateCommand`, `containerEnv` and `remoteUser` —
  the SDK install becomes a manual script run each session.
- **(C) Deal with B, then move off the free tier.** A small VPS makes storage stop mattering;
  GitHub Actions on push is the other route that costs no storage at all.

**(C) is the recommendation.** Free-tier custody of a 16 GB toolchain container is a poor use
of effort, and the framework decision may mean most of this box is unnecessary anyway.

## gh quirks found in practice

- `gh codespace logs` fails with `vscode@localhost: Permission denied (publickey,password)`.
  Use `gh codespace ssh -c <name> -- <cmd>` probes instead.
- `gh codespace machine` does **not** exist in gh 2.45.0. Use
  `gh api /repos/<owner>/<repo>/codespaces/machines`. Only `basicLinux32gb` (2c/8G/32G) and
  `standardLinux32gb` (4c/16G/32G) are offered.
- Cold create to `Available` took **under 1 minute** in WestEurope (twice), so the old
  "~10 min" figure referred to the SDK download, not provisioning.
- `git` in the Operit proot has **no identity configured**; a commit fails with
  `unable to auto-detect email address` and the subsequent push silently sends an empty
  branch pointer. Set `user.name`/`user.email` before committing.
- Heredocs through the Operit terminal wrapper are unreliable; write scripts with
  `create_file`/`python3` instead.
