#!/usr/bin/env bash
#
# Sets up three repositories under ~/Documents/Work/opensource:
#
#   1. ./am32-geprc-taker-h65/  (this folder)  --> public helper repo with the flash kit
#   2. ../AM32/                                --> clone of am32-firmware/AM32, on branch
#                                                  add-geprc-taker-h65-target with the
#                                                  Inc/targets.h change applied & committed
#   3. ../am32-wiki/                           --> clone of am32-firmware/am32-wiki,
#                                                  on branch add-geprc-taker-h65-guide with
#                                                  the new flashing guide applied & committed
#
# After this runs you can:
#   - cd ../AM32       && git push origin add-geprc-taker-h65-target    (after setting your fork as origin)
#   - cd ../am32-wiki  && git push origin add-geprc-taker-h65-guide     (after setting your fork as origin)
#   - cd .             && git remote add origin <your repo url> && git push -u origin main
#
# Or use `gh` cli if you have it:
#   - gh repo fork am32-firmware/AM32 --remote --org <you>
#   - gh repo fork am32-firmware/am32-wiki --remote --org <you>
#
# Sets per-repo git identity so it works without a global ~/.gitconfig.
# Change AUTHOR_NAME / AUTHOR_EMAIL below if you want different attribution.

set -euo pipefail

AUTHOR_NAME="Tomás Sasovsky"
AUTHOR_EMAIL="to.sasovsky@gmail.com"

HERE="$(cd "$(dirname "$0")" && pwd)"
PARENT="$(cd "$HERE/.." && pwd)"

cd "$HERE"

# ---------------- 0. Clean up any sandbox-created broken state ----------------
# The cowork sandbox may have left partial .git directories or empty AM32/ folders
# in the mounted opensource directory that root-owned processes left undeletable
# from inside the sandbox. They have to be cleaned from a real user shell.

echo "==> Cleaning up sandbox-created broken state (may need sudo)"

clean_broken_path() {
  local path="$1"
  if [[ -e "$path" ]]; then
    if rm -rf "$path" 2>/dev/null; then
      echo "    removed $path"
    else
      echo "    rm -rf failed for $path, trying with sudo..."
      sudo rm -rf "$path"
      echo "    removed $path (with sudo)"
    fi
  fi
}

clean_broken_path "$HERE/.git"
clean_broken_path "$PARENT/AM32"
clean_broken_path "$PARENT/am32-wiki"

# ---------------- 1. Helper repo (this folder) ----------------

echo "==> Setting up helper repo at $HERE"

git init -b main
git config user.name "$AUTHOR_NAME"
git config user.email "$AUTHOR_EMAIL"

# Don't track upstream/ contents in this repo's main branch - those are for the upstream PRs
echo "upstream/" >> .gitignore.tmp
cat .gitignore >> .gitignore.tmp 2>/dev/null || true
mv .gitignore.tmp .gitignore

git add .
git commit -m "Initial commit: flash kit for AM32 on GEPRC TAKER H65_8S_32Bit 65A 4IN1

Includes:
- flash_am32.sh: probe-rs based flasher with full/erase/info/verify/fw-only modes
- firmware/: AM32 bootloader (PA0/PA2/PA15/PB4 variants) + AM32 firmware
  (AT32DEV - the working one, GEPRC_4IN1 - reference of the broken target)
  + default EEPROM
- README explaining the pin mismatch issue with the official target

Tested on the GEPRC TAKER H743 BT 32Bit 65A stack (TAKER H65_8S_32Bit 65A
4IN1 ESC), all 4 AT32F421K8U7 MCUs flashed and verified working under
Betaflight DShot at 15-20% throttle on the bench."

echo "    Done. Helper repo initialized on branch main."
echo

# ---------------- 2. AM32 firmware repo ----------------

AM32_DIR="$PARENT/AM32"
echo "==> Setting up AM32 firmware repo at $AM32_DIR"

if [[ -d "$AM32_DIR" ]]; then
  echo "    $AM32_DIR already exists, skipping clone."
  echo "    Delete it manually if you want this script to re-clone."
else
  git clone https://github.com/am32-firmware/AM32.git "$AM32_DIR"
fi

cd "$AM32_DIR"
git config user.name "$AUTHOR_NAME"
git config user.email "$AUTHOR_EMAIL"

# Make sure we're on main (or master) and up to date
DEFAULT_BRANCH=$(git symbolic-ref --short HEAD)
echo "    Default branch: $DEFAULT_BRANCH"

# Create feature branch (or reset if already exists)
if git show-ref --quiet refs/heads/add-geprc-taker-h65-target; then
  echo "    Branch add-geprc-taker-h65-target already exists, switching to it."
  git checkout add-geprc-taker-h65-target
else
  git checkout -b add-geprc-taker-h65-target
fi

# Apply the targets.h change. We do this as a literal text insertion rather than
# a git apply, because the patch file has placeholder ISSUE URL text that needs
# manual replacement before commit anyway.
python3 << PYEOF
import re, pathlib

p = pathlib.Path("Inc/targets.h")
src = p.read_text()

new_block = """

#ifdef GEPRC_TAKER_H65_F421
#define FIRMWARE_NAME "GEPRC TKR H65"
#define FILE_NAME "GEPRC_TAKER_H65_F421"
#define DEAD_TIME 75
#define HARDWARE_GROUP_AT_045
#define HARDWARE_GROUP_AT_B
#define USE_SERIAL_TELEMETRY
#endif

"""

# Check if already applied (idempotent re-runs)
if "GEPRC_TAKER_H65_F421" in src:
    print("    Already applied, skipping.")
    raise SystemExit(0)

# Insert right after the existing GEPRC_4IN1_F421 block.
pattern = re.compile(
    r"(#ifdef GEPRC_4IN1_F421\n"
    r"#define FIRMWARE_NAME \"Geprc 4in1 \"\n"
    r"#define FILE_NAME \"GEPRC_4IN1_F421\"\n"
    r"#define DEAD_TIME 75\n"
    r"#define HARDWARE_GROUP_AT_540\n"
    r"#define HARDWARE_GROUP_AT_E\n"
    r"#define USE_SERIAL_TELEMETRY\n"
    r"#endif\n)"
)
m = pattern.search(src)
if not m:
    print("ERROR: could not find anchor block (GEPRC_4IN1_F421 target) in Inc/targets.h")
    print("       Upstream may have changed. Apply the patch manually:")
    print(f"       see {pathlib.Path('../am32-geprc-taker-h65/upstream/AM32-targets-h.patch')}")
    raise SystemExit(1)

new_src = src[:m.end()] + new_block + src[m.end():]
p.write_text(new_src)
print("    Inserted GEPRC_TAKER_H65_F421 target after GEPRC_4IN1_F421.")
PYEOF

git add Inc/targets.h
if git diff --cached --quiet; then
  echo "    No changes to commit (already applied)."
else
  git commit -m "Add GEPRC_TAKER_H65_F421 target

The existing GEPRC_4IN1_F421 target uses HARDWARE_GROUP_AT_E (PA2 input)
and HARDWARE_GROUP_AT_540 (phase comp A=PA5, B=PA4, C=PA0), which do not
match the GEPRC TAKER H65_8S_32Bit 65A 4IN1 ESC sold as part of the
TAKER H743 BT 32Bit 65A stack.

That board uses HARDWARE_GROUP_AT_B (PB4 input, TMR3 CH1) and
HARDWARE_GROUP_AT_045 (phase comp A=PA0, B=PA4, C=PA5). Confirmed
across all 4 AT32F421K8U7 MCUs on the 4-in-1: passthrough enumerates,
DShot drives motors, sinusoidal startup is clean at 15-20% throttle.

Adding a new target rather than modifying GEPRC_4IN1_F421 in case any
older GEPRC board in the wild matches the original target's pin config.

See discussion at <ISSUE URL TBD>."
fi

echo "    Done. AM32 repo on branch add-geprc-taker-h65-target."
echo

# ---------------- 3. AM32 wiki repo ----------------

WIKI_DIR="$PARENT/am32-wiki"
echo "==> Setting up am32-wiki repo at $WIKI_DIR"

if [[ -d "$WIKI_DIR" ]]; then
  echo "    $WIKI_DIR already exists, skipping clone."
else
  git clone https://github.com/am32-firmware/am32-wiki.git "$WIKI_DIR"
fi

cd "$WIKI_DIR"
git config user.name "$AUTHOR_NAME"
git config user.email "$AUTHOR_EMAIL"

if git show-ref --quiet refs/heads/add-geprc-taker-h65-guide; then
  echo "    Branch add-geprc-taker-h65-guide already exists, switching to it."
  git checkout add-geprc-taker-h65-guide
else
  git checkout -b add-geprc-taker-h65-guide
fi

# Copy in the new guide
mkdir -p docs/guides
cp "$HERE/upstream/Flashing-GEPRC-TAKER-H65.md" docs/guides/Flashing-GEPRC-TAKER-H65.md

# Add the guide to the sidebar (VitePress config). The sidebar is in .vitepress/config.*
SIDEBAR_FILE=$(find .vitepress -maxdepth 2 -name "config.*" 2>/dev/null | head -1)
if [[ -n "$SIDEBAR_FILE" ]]; then
  echo "    Note: the guide file is added, but you'll need to register it in $SIDEBAR_FILE manually."
  echo "    Look for the existing Flashing-Tekko32-45A-Single-ESC entry and add a sibling for the new guide."
fi

git add docs/guides/Flashing-GEPRC-TAKER-H65.md
if git diff --cached --quiet; then
  echo "    No changes to commit (already applied)."
else
  git commit -m "Add Flashing-GEPRC-TAKER-H65 guide

A probe-rs based, macOS-friendly flashing guide for the GEPRC TAKER
H65_8S_32Bit 65A 4IN1 ESC (Artery AT32F421x4). The existing AT32F421
guide (Flashing-Tekko32-45A-Single-ESC) is Windows + Keil only.

Includes:
- Why the official GEPRC_4IN1_F421 target does not fit this board
- SWD fly-soldering instructions (the board does not expose SWD pads)
- probe-rs install and verify steps
- Per-MCU flash sequence with the bootloader/firmware/EEPROM addresses
- Long-range AM32 settings recommendations
- Troubleshooting table

See discussion at <ISSUE URL TBD>."
fi

echo "    Done. am32-wiki repo on branch add-geprc-taker-h65-guide."
echo

# ---------------- Summary ----------------

echo "============================================================"
echo "All three repos are ready."
echo
echo "Helper repo:   $HERE  (branch: main)"
echo "AM32 firmware: $AM32_DIR  (branch: add-geprc-taker-h65-target)"
echo "AM32 wiki:     $WIKI_DIR  (branch: add-geprc-taker-h65-guide)"
echo
echo "Next steps (after filing the upstream issue):"
echo "  1. Create a public GitHub repo for am32-geprc-taker-h65 and push main."
echo "  2. Fork am32-firmware/AM32 and am32-firmware/am32-wiki on GitHub."
echo "  3. Add your forks as origin (or rename existing remote) and push the branches."
echo "  4. Replace '<ISSUE URL TBD>' in the commit messages and the PR bodies"
echo "     with the actual issue URL once it's filed. (Use 'git commit --amend' or"
echo "     mention it in the PR description.)"
echo "============================================================"
