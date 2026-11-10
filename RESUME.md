# RESUME HERE — project state, 2026-11-10

Read this first, then `README.md`. This file is the "where were we" note; the README is the
"how to do it" recipe. Everything below was measured on a real codespace on 2026-11-10, not
predicted. Anything unverified is marked **UNVERIFIED** on purpose — do not silently upgrade
those lines to facts later.

## The one-line status

The boxes work and cost nothing on the free tier. **There is still no Android app in this
repo**, so `assembleDebug` has never run. The next real decision is the framework.

## What is settled (do not reopen casually)

- **Platform:** GitHub. Repo `strideberg2-ship-it/android-buildbox`, deliberately **public**
  (user's call, "better terms"), Codespaces for the box, Actions as the build fallback.
  Oracle Cloud is scratched for now, not forever.
- **Option B is the design:** the repo carries **no `.devcontainer/` at all**. That is the
  only way Codespaces gives you its default (`universal`) image, and only a default image
  gets free base-container storage. Naming *any* image — including stock `universal` — makes
  the whole container billable.
- **The cost thesis is proven, not argued.** A codespace created from this repo reported
  `devcontainer-info` → `Definition ID: universal`, `Source code repository:
  https://github.com/devcontainers/images`, `Image version: 6.1.12`.
- **The universal image is richer than the devcontainer it replaced.** It already ships
  `openjdk` 25.0.5, `/usr/bin/gh`, `node v24.22.2` and `gradle` (9.8.2, via sdkman). The
  java / github-cli / sshd features were never load-bearing. What Option B costs is only
  `postCreateCommand` automation, i.e. one manual `bash scripts/bootstrap.sh` per fresh box.
- **`bootstrap.sh` is idempotent, re-proven under Option B.** Second run: every step skipped,
  `EXIT=0`, exactly one `android-buildbox:start` block in `~/.bashrc`, sizes unchanged
  (SDK 437 MB, `~/.gradle` 172 K).

## The one wrinkle, and the fix

The default JDK is **25**, which AGP does not support. Fix, with no download:

```bash
sdk default java 21.0.13-ms     # or: sdk use java 21.0.13-ms
java -version                   # expect 21.x
```

Both 21.0.13 and 25.0.5 are already on disk at `/usr/local/sdkman/candidates/java/`. Run this
after `bootstrap.sh`, before the first Gradle build. **Never exercised against a real project
yet** — there is no project.

## Numbers worth keeping (measured, 2026-11-10)

| Thing | Value |
|---|---|
| Free quota (GitHub Free personal) | 15 GB-month storage + 120 core-hours |
| Compute / storage overage | $0.18/hr (2-core), $0.07/GB-month |
| No payment method | usage is **blocked** at quota, never overspent |
| Default-image box, base container storage | **free** |
| Custom-image box (the retired design) | ~16 GB billed — one box eats the month |
| Inside the box, `df -h /` | `overlay 32G 12G 19G 39% /` (~11 G of that is the base image) |
| `~/android-sdk` | 437 MB |
| `/usr/local/sdkman` | 916 MB |
| `~/.gradle` (empty cache) | 172 K |
| Cold create → `Available` | under 1 minute (WestEurope, twice) |

Machine used: `basicLinux32gb` (2-core / 8 GB / 32 GB). `standardLinux32gb` also exists.
`gh codespace machine` does not exist in gh 2.45.0 — use
`gh api /repos/<owner>/<repo>/codespaces/machines`.

## Repo state at the time of writing

- `main` = the Option B design, verified. `option-b` points at the same commit.
- `default-image` (older branch) holds the failed middle experiment: it removed only the
  `image:` key, and Codespaces then fell back to **`base-alpine`** — no java, no `gh`, no
  node, `bootstrap.sh` could not even run. Kept as evidence, not as a candidate.
- Working tree: `README.md`, `RESUME.md`, `devcontainer-notes.md`, `.gitignore`,
  `scripts/bootstrap.sh`, `scripts/backup.sh`. No app.
- **Zero codespaces alive.** Confirmed after teardown. Leave it that way between sessions.

## The next step, in order

1. **Choose the framework.** This is the blocker; a perfect free box still produces no APK.
   The trade-offs are already researched and written down — see `devcontainer-notes.md` and
   the §7 "Adding a framework later" section of the README. Short version:
   Kotlin/Compose has the cleanest headless build but the worst edit-install-retest loop;
   Flutter is the same loop with an easier build command; Expo/React Native is the only
   plausible *adb-free* loop but leans on Expo's tunnel; React web/PWA needs no Android
   toolchain at all. Whichever wins, Flutter and Node need a step added to `bootstrap.sh` —
   there is no devcontainer feature mechanism left to lean on.
2. **Put a minimal "hello world" project in this repo** for the chosen framework and get one
   real `assembleDebug` (or equivalent) to succeed on a codespace. That is the first actual
   APK, and it also tests the JDK 21 switch for real.
3. Then the everyday loop: box up → `bootstrap.sh` → `sdk default java 21.0.13-ms` → build →
   pull the APK off the box (`scp` / `gh codespace cp`) → `termux-open` it → delete the box.

## Do not do these

- **Do not re-add a `.devcontainer/`.** Not "just to set `postCreateCommand`", not "just to
  pin the image". It converts a free box into a ~16 GB/month bill. The warning also appears
  in README Step B1, Step C, §3 and at the top of `scripts/bootstrap.sh`.
- **Do not specify `image:` even as `mcr.microsoft.com/devcontainers/universal`.** You already
  get that image for free by *not* configuring anything.
- **Do not leave a codespace running.** It burns core-hours and storage while idle; delete it
  when done. `gh codespace delete -c <name> -f`, then `gh codespace list` to confirm.
- **Do not commit keystores, `google-services.json`, tokens or `.env`.** `.gitignore` already
  blocks them; see README §6.

## Phone-side setup that is NOT in this repo (the fragile part)

The `gh`/`git` surface used to drive all of this lives inside Operit's Ubuntu proot at
`/root`, **not** in Termux. It is app data, so it disappears on an Operit reinstall or a
clear-data. It is not backed up anywhere and no secrets are written down here.

What has to exist again on a fresh proot:

- `gh` 2.45.0 installed (`apt install gh`), logged in with at least the `codespace` scope.
  `gh config get git_protocol` should say `ssh`.
- An ssh key for GitHub, e.g. `~/.ssh/id_ed25519_operit`, with only the **public** half
  pasted at github.com/settings/ssh/new, and `~/.ssh/config` pinning it
  (`IdentitiesOnly yes`). The private half never leaves the proot.
- Git identity, or every commit fails with "unable to auto-detect email address" and the
  push then sends an empty branch pointer that *looks* like success:
  `git config --global user.name "strideberg2-ship-it"` and
  `git config --global user.email "272692333+strideberg2-ship-it@users.noreply.github.com"`.
- `stty rows 500 cols 200` in `~/.bashrc`. The Operit terminal wrapper is 60x40, and output
  taller than the tty is what truncates command results — **not** heredocs, which work fine.

Termux is a separate environment with its own PAT and its own key; do not copy keys between
the two, and do not assume a Termux credential works from the proot.

## Habits that saved time (keep them)

- **Read the tool output.** Twice during this project a commit was issued and its result
  never read; both times the state had to be re-derived. An unread result is not evidence.
- **`grep -c '^```' README.md`** should be **even**. An odd count means a stray fence is
  mispairing every code block below it — this caught a real self-inflicted bug.
- Prefer `create_file` + `python3 file.py` over heredocs for multi-line edits through the
  Operit terminal, and pass `environment: linux` or the write fails with a misleading
  "No such file or directory".
- Verify pushes with `git ls-remote --heads origin` rather than trusting the push output.
