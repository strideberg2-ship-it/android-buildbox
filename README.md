# Android build box — re-spin recipe

Everything you need to go from "nothing" to "APK built" in about 10 minutes, on a phone.
Two hosts, one file set: GitHub Codespaces now, any Linux VPS later.

**Design rule:** the repo holds *configuration*. Nothing important lives only on the box.
So the recipe is always: **clone → bootstrap → build**. Backup adds at most a small tarball.

> Status: drafts. The two shell scripts have been syntax-checked and run against stubs on the
> phone (see `devcontainer-notes.md` — three real bugs were found and fixed that way).
> Nothing has touched a codespace, a container image, or Google's download servers, so all
> versions and all Codespaces behaviour are **unverified**.

---

## 0. Where the files go

```
android-buildbox/
├── .devcontainer/
│   ├── devcontainer.json      <- from this folder
│   └── bootstrap.sh           <- from this folder, chmod +x
├── scripts/
│   └── backup.sh              <- from this folder, chmod +x
├── .gitignore                 <- from this folder
├── README.md                  <- from this folder
├── devcontainer-notes.md      <- from this folder
└── ...your app
```

Putting the files in the repo is the whole point — a fresh clone rebuilds the box.

---

## 1. Get the repo onto the phone

Run this in **Termux**, not in a file manager. Do not clone into `/sdcard` — git on shared
storage is slow and breaks on permissions; clone into the Termux home.

```bash
pkg install -y git gh            # skip if both already answer --version
gh auth status                   # must say "Logged in to github.com"
gh api user --jq .login          # prints your username — a sanity check, nothing else
```

**If you ran `gh config set -h github.com git_protocol ssh` and got**
`HTTP 403: Resource not accessible by personal access token (/user/keys)`:
that is `gh` checking whether your SSH key is on the account. Your token is a fine-grained PAT
without the "Git SSH keys" permission. The setting **did** apply — the warning is about the
check, not the config. Two ways forward:

- **Use HTTPS instead (recommended here):** `gh config set -h github.com git_protocol https`.
  `gh` already holds a working token, so clone and push need no SSH key at all.
- **Stay on SSH:** add the key yourself. `cat ~/.ssh/id_ed25519.pub` (create one first with
  `ssh-keygen -t ed25519 -C phone` if that file is missing), paste it at
  github.com → Settings → SSH and GPG keys → New SSH key, then
  `ssh -T git@github.com` must answer `Hi <you>! You've successfully authenticated`.
  Once that reply appears you are done with this section — keep the ssh setting and go on to
  Step A below. Do not re-run `gh config set`.

This matters for Step B: with SSH selected, `gh repo clone` and `git push` use
`git@github.com:` URLs, so an unregistered key fails the clone, not just the warning.

**Before anything else:** the drafts sit in `/sdcard`, so Termux needs storage access once.
If `ls /sdcard/Download` already works, skip this.

```bash
termux-setup-storage             # tap Allow on the Android prompt
```

### Step A — does the repo exist yet?

```bash
gh repo view "$(gh api user --jq .login)/android-buildbox" --json name,visibility
```

Prints JSON if it exists. Errors with `Could not resolve to a Repository` if it does not.
Branch on that, then run exactly one of the two blocks below.

### Step B1 — it does not exist: create it from the drafts

```bash
D=/sdcard/Download/Operit/android-buildbox    # drafts
T=~/android-buildbox                          # repo

mkdir -p "$T/.devcontainer" "$T/scripts"
cp "$D/devcontainer.json" "$D/bootstrap.sh"    "$T/.devcontainer/"
cp "$D/backup.sh"                              "$T/scripts/"
cp "$D/.gitignore" "$D/README.md" "$D/devcontainer-notes.md" "$T/"
chmod +x "$T/.devcontainer/bootstrap.sh" "$T/scripts/backup.sh"

cd "$T"
git init -b main
git add -A
git commit -m "devcontainer: android build box"
gh repo create android-buildbox --public --source=. --remote=origin --push
```
**Actual state 2026-11-10: the repo is PUBLIC.** The original draft said `--private`, but the
repo was created public and the user confirmed public is the intended state (recalled reason:
better terms — that recall is unverified, but the choice was deliberate). Content currently
carries no credentials. Treat visibility as a real setting, not a comment in a code block;
check it with `gh repo view --json visibility` before assuming.

Public repos get unlimited Actions minutes, private ones 2,000/month; you are far from either
limit. Codespaces works either way.

### Step B2 — it exists: clone it, then copy the drafts in

```bash
T=~/android-buildbox
gh repo clone "$(gh api user --jq .login)/android-buildbox" "$T"

D=/sdcard/Download/Operit/android-buildbox    # drafts
mkdir -p "$T/.devcontainer" "$T/scripts"
cp "$D/devcontainer.json" "$D/bootstrap.sh"    "$T/.devcontainer/"
cp "$D/backup.sh"                              "$T/scripts/"
cp "$D/.gitignore" "$D/README.md" "$D/devcontainer-notes.md" "$T/"
chmod +x "$T/.devcontainer/bootstrap.sh" "$T/scripts/backup.sh"

cd "$T" && git add -A && git commit -m "devcontainer: android build box"
git push
```

### Step C — confirm before you spend a codespace on it

```bash
ls -A ~/android-buildbox ~/android-buildbox/.devcontainer ~/android-buildbox/scripts
```

Expect exactly six files and nothing else:

```
~/android-buildbox:  .gitignore  README.md  devcontainer-notes.md  (.git)
.devcontainer/:      devcontainer.json  bootstrap.sh
scripts/:            backup.sh
```

**Do not use `cp -r *` for this.** It silently skips `.gitignore`, and the draft folder and the
repo have the same name, so a loose `cp -r` can copy the folder into itself.

### Step D — things that were UNVERIFIED and are now confirmed
All of the following were checked on 2026-11-10 by creating a real codespace and probing it:

- Base image `ubuntu-24.04` resolves → `Ubuntu 24.04.3 LTS`.
- `ghcr.io/devcontainers/features/java:1` with `version: 21`, `jdkDistro: ms`,
  `installGradle: true`, `gradleVersion: 8.14` → **all four option names correct**;
  JDK 21.0.13 Microsoft build, Gradle 8.14.6 via `/usr/local/sdkman`.
- `ghcr.io/devcontainers/features/github-cli:1` → `/usr/bin/gh`.
- `ghcr.io/devcontainers/features/sshd:1` → `/usr/sbin/sshd` + host keys generated.
  The "base image probably already ships sshd" worry was unnecessary.
- `bootstrap.sh` runs correctly as `postCreateCommand`: cmdline-tools `11076708_latest`
  unpacked to `cmdline-tools/latest/bin`, 8 licence files written, `platforms/android-35`
  and `build-tools/35.0.0` installed, `.bashrc` marker block added exactly once.
- Idempotency is real, not claimed: re-running `bootstrap.sh` inside the live box skipped
  every step, exited 0, and did not duplicate the `.bashrc` block.

---

## 1b. First run (once)

Assumes the steps above are done and `~/android-buildbox` exists.

```bash
cd ~/android-buildbox
gh codespace create --machine basicLinux32gb
```

- No `--repo` needed: run inside the clone and `gh` reads the remote from `.git`. This is why
  Step C matters — a missing remote is the usual cause of "could not determine repository".
- `basicLinux32gb` = 2 core / 8 GB / 32 GB, the free shape. **UNVERIFIED machine-type
  name** — if it errors, run `gh codespace create` with no machine flag and pick from the
  list it prints.
- If the CLI gripes, create it in the browser: repo → Code → Codespaces → New codespace.

First create runs `postCreateCommand` → `bootstrap.sh`, which downloads the Android SDK.
**Expect 5–10 minutes.** Watch it:

```bash
gh codespace ssh          # enter the box; if bootstrap is still running you land on a
                          # normal shell, so check the log:
tail -f /workspaces/.codespaces/.persistedshare/creation.log   # UNVERIFIED path
```

Sanity check once inside:

```bash
sdkmanager --list_installed | head      # the SDK is there
gradle --version                        # or ./gradlew --version
```

---

## 2. Everyday use

```bash
gh codespace ssh
cd /workspaces/android-buildbox
./gradlew assembleDebug
```

The APK lands at `app/build/outputs/apk/debug/app-debug.apk`
(Flutter would be `build/app/outputs/flutter-apk/app-debug.apk`).

### Getting the APK onto the phone

adb is off the table (wireless debugging breaks your banking app), so pick one:

**A. Via GitHub Actions (most robust, zero standing infrastructure)**
Push, let CI build, then on the phone:

```bash
gh run download                # run inside ~/android-buildbox; picks the latest artifact
unzip app-debug.zip && termux-open app-debug.apk
```

`termux-open` → Android's installer → tap Install. Enable "install unknown apps" for
Termux once. This route also means you never need the codespace open at all.

**B. Direct copy from the codespace**
`gh codespace cp` exists in recent `gh`, but its flags are **UNVERIFIED** here — try
`gh codespace cp -e -c <codespace> remote:app/build/outputs/apk/debug/app-debug.apk ~/`
and read `gh codespace cp --help` if it complains.

Then, in either case: **tap install, watch the screen, read logs in the app**.
No `logcat` in this loop by design — build a debug screen or use an in-app log viewer.

---

## 3. The storage problem (this is the real constraint)

Codespaces free (GitHub Free personal) = **120 core-hours + 15 GB-month storage**; Pro gives
180 hrs / 20 GB-month. Prices if you exceed: $0.18/hr for a 2-core box, $0.07 per GB-month.
With no payment method on file, usage is simply *blocked* at the quota — you cannot lose money
here, you can only get stuck until the month rolls over.

### What actually eats the quota (measured 2026-11-10, not estimated)
The SDK is **not** the problem. Measured inside a live `basicLinux32gb` codespace:

| Thing | Size |
|---|---|
| `~/android-sdk` total | **437 MB** |
| — cmdline-tools | 148 MB |
| — build-tools 35.0.0 | 147 MB |
| — platforms/android-35 | 142 MB |
| `~/.gradle` before any build | 252 KB |
| `/usr/local/sdkman` (Gradle via feature) | 500 MB |

The earlier "10–15 GB" figure in this README was wrong by an order of magnitude and has been
removed. The real constraint is the **container image**: with
`"image": "mcr.microsoft.com/devcontainers/base:ubuntu-24.04"` the loop image was **~16 GB**,
which alone exceeds the whole monthly quota.

### Why there is no `image:` key in devcontainer.json
Per GitHub's billing docs, storage of a base dev container built from the **default image is
free** and does not count against the quota — *even if you add features on top*. If the config
specifies a custom `image` (or a Dockerfile), the **entire container** counts, plus all files.
So dropping `image:` is not a style choice; it is the single change that moves ~16 GB of billed
storage off the ledger. Do not add an `image:` back without understanding this.

Verify which image a codespace actually used:
```bash
devcontainer-info
```
Default image prints `Definition ID: universal` and
`Source code repository: https://github.com/devcontainers/images`. If instead it names a
different source, you are paying for the container and should check the config.

**Rule: delete the codespace when you finish a work session.**

```bash
gh codespace list
gh codespace delete -c <codespace>      # confirm with -f or the prompt
```

Next session: `gh codespace create` again (cold create was measured at **under 1 minute** to
`Available` in WestEurope, plus a couple of minutes for the SDK download in `postCreateCommand`;
the old "~10 min" figure was pessimistic).

**RESOLVED 2026-11-10:** storage is a *cumulative* monthly figure, not a live balance. GitHub's
docs state plainly that deleting a codespace does **not** reduce this month's used-storage
number — it only reduces the rate at which it accumulates. So there is nothing to "measure for
a billing cycle"; the earlier UNVERIFIED note was asking the wrong question. Practical rule:
delete promptly, and judge the effect next month, not today.

**Quirks found in practice:**
- `gh codespace logs` fails here with `vscode@localhost: Permission denied (publickey,password)`.
  Use `gh codespace ssh -c <name> -- <command>` probes instead of reading postCreate logs.
- `gh codespace machine` **does not exist** in gh 2.45.0. List machine types with
  `gh api /repos/<owner>/<repo>/codespaces/machines`. The only two available were
  `basicLinux32gb` (2 core / 8 GB / 32 GB) and `standardLinux32gb` (4 core / 16 GB / 32 GB).
- Heredocs (`cmd <<'EOF'`) are unreliable through the Operit terminal wrapper; write files with
  `python3 -c` / `python3 file.py` instead.

**Alternative when you just want an APK:** skip Codespaces entirely and use GitHub Actions
on push. Android SDK + build-tools are preinstalled on the runner, so builds are fast and
cost no storage. Cost: ~2,000 minutes/month included, free for public repos.

---

## 4. Backup (only when you change machine)

```bash
bash scripts/backup.sh                # -> ~/backups/buildbox-state-<stamp>.tar.gz
```

Small: git identity, gradle.properties, local.properties, .vscode, your notes. Not the SDK,
not caches. Get it off the box — from Termux:

```bash
gh codespace cp -e -c <codespace> remote:/home/vscode/backups/. ./buildbox-backups/
```

(Or simply keep the things you care about *in the repo* and skip backups. That is the
better habit at this scale.)

---

## 5. Migrating to a VPS later

Nothing in the repo knows about Codespaces. On the VPS:

```bash
# one-time
apt install -y git docker.io docker-compose-v2   # whatever your distro calls it
git clone <you>/android-buildbox && cd android-buildbox
#  <you> = your GitHub username; from the phone, `gh api user --jq .login` prints it
```

The devcontainer spec has a standard escape hatch:

```bash
npm i -g @devcontainers/cli        # UNVERIFIED package/command names for current release
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . bash -lc './gradlew assembleDebug'
```

That gives you the same image, same bootstrap, same env — without VS Code. If the CLI is
awkward, the fallback is dumb and reliable: a `Dockerfile` that is just the base image
plus `bootstrap.sh` copied in, run with `docker compose up -d`, then `docker exec`.
Unpack your backup tarball into the container's `$HOME` and you are home.

**What does NOT migrate:** the codespace itself, `gh codespace ssh`, and the assumption
of free storage. On a paid box disk stops being the constraint, so you can keep the SDK
and Gradle cache permanently — the main real benefit of paying.

---

## 6. Signing and secrets (later, not now)

Debug builds self-generate `~/.android/debug.keystore`. **You need nothing today.**

When you do want release builds:

- Keystore + `google-services.json` live in **GitHub Actions secrets** (base64 the
  keystore), decoded only inside the CI job, deleted at job end.
- Or a local `~/.gradle/gradle.properties` on the box pointing at a keystore path —
  never in the repo, never in a backup archive (the backup script refuses).
- `.gitignore` already blocks `*.jks`, `*.keystore`, `google-services.json`,
  `keystore.properties`, `.env`.

If a keystore ever lands in a commit, assume it is burned and rotate.

---

## 7. Adding a framework later

Core = JDK + Android SDK + Gradle. That covers Kotlin/Compose as-is.

- **Flutter**: add `ghcr.io/devcontainers/features/...` alternative or a step in
  `bootstrap.sh` that clones Flutter into `~/flutter` and puts `flutter/bin` on PATH.
  ~1–2 GB extra. **Unverified** exact size.
- **Node / RN / Expo**: add the `node` devcontainer feature. Or, for Expo, skip the box
  for the dev loop entirely (`npx expo start --tunnel` + Expo Go on the phone).
- **React web/PWA**: no Android SDK needed at all; this whole box is oversized for it.

Do not add these to `devcontainer.json` yet — an unused framework layer costs storage you
do not have.
