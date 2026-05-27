#!/usr/bin/env bash
#
# AM32 flasher for GEPRC TAKER H65_8S_32Bit 65A 4IN1 (Artery AT32F421)
# via ST-Link V2 + SWD on macOS, using probe-rs.
#
# Why probe-rs and not OpenOCD?
#   OpenOCD's stm32f1x driver does not recognize Artery's device ID 0x50020112
#   (it only knows ST's IDs), so it errors with "Cannot identify target as a
#   STM32 family." probe-rs ships native AT32F4 support via CMSIS-Pack since v0.21.
#
# Install (one-time):
#   brew install probe-rs/probe-rs/probe-rs
#   # OR via cargo:
#   cargo install probe-rs-tools --locked
#
# Usage:
#   ./flash_am32.sh                  # default: PA2 bootloader, full flash
#   ./flash_am32.sh PA2              # explicit pin choice
#   ./flash_am32.sh PB4              # try a different signal input pin
#   ./flash_am32.sh PA2 info-only    # just connect + read chip info (sanity check)
#   ./flash_am32.sh PA2 erase-only   # mass-erase the chip (also removes BLHeli_32 RDP)
#   ./flash_am32.sh PA2 verify-only  # verify flashed contents against local hex files
#   ./flash_am32.sh PB4 fw-only      # just rewrite the firmware @ 0x08001000 (no erase, no bootloader)
#
# Override the firmware hex file (e.g., to switch from GEPRC_4IN1 → AT32PB4_540):
#   FW=AM32_AT32PB4_540_F421_2.20.hex ./flash_am32.sh PB4 fw-only
#
# Memory map for AT32F421 (32 KB AM32 footprint):
#   0x08000000  bootloader (4 KB)         - AM32_F421_BOOTLOADER_<PIN>_V17.hex
#   0x08001000  firmware   (27 KB)        - AM32_GEPRC_4IN1_F421_2.20.hex (already offset)
#   0x08007C00  default EEPROM (1 KB)     - eeprom_version_1_7c00.bin

set -euo pipefail

PIN="${1:-PA2}"
MODE="${2:-full}"
HERE="$(cd "$(dirname "$0")" && pwd)"

# Chip target name in probe-rs. The "K8U7" suffix means QFN32 / 64KB flash,
# which is the part on the GEPRC TAKER H65 ESCs. The flash algorithm is
# shared across all AT32F421x8 variants so this name is safe even if the
# physical chip turns out to be a sibling like C8T7 (LQFP48).
CHIP="${AT32_CHIP:-AT32F421K8U7}"

BOOT_HEX="$HERE/firmware/AM32_F421_BOOTLOADER_${PIN}_V17.hex"
# Default firmware: AT32PB4_540 (PB4 input + 540 phase routing, matches our hardware).
# Override with `FW=...hex` env var if needed.
FW_HEX="$HERE/${FW:-AM32_AT32PB4_540_F421_2.20.hex}"
EEPROM_BIN="$HERE/firmware/eeprom_version_1_7c00.bin"
LOG="$HERE/logs/flash_$(date +%Y%m%d-%H%M%S)_${PIN}.log"

mkdir -p "$HERE/logs"

# ---------------- helpers ----------------
log() { printf '%s\n' "$*" | tee -a "$LOG"; }
hr()  { log "------------------------------------------------------------"; }
die() { log "ERROR: $*"; exit 1; }
require_file() { [[ -f "$1" ]] || die "missing file: $1"; }

# Wrapper: every probe-rs invocation goes through this so we get consistent
# logging and a chip flag we don't repeat.
prs() {
  log ">>> probe-rs $*"
  probe-rs "$@" --chip "$CHIP" 2>&1 | tee -a "$LOG"
}

# ---------------- preflight ----------------
hr
log "AM32 flasher for GEPRC TAKER H65 (Artery AT32F421)"
log "Pin variant : $PIN"
log "Mode        : $MODE"
log "Chip target : $CHIP"
log "Bootloader  : $BOOT_HEX"
log "Firmware    : $FW_HEX"
log "EEPROM      : $EEPROM_BIN"
log "Log         : $LOG"
hr

require_file "$BOOT_HEX"
require_file "$FW_HEX"
require_file "$EEPROM_BIN"

if ! command -v probe-rs >/dev/null 2>&1; then
  die "probe-rs not found. Install with:
       brew install probe-rs/probe-rs/probe-rs
       # OR
       cargo install probe-rs-tools --locked"
fi

log "probe-rs version: $(probe-rs --version 2>&1 | head -1)"
log "Connected probes:"
probe-rs list 2>&1 | tee -a "$LOG"
hr

# ---------------- modes ----------------
do_info() {
  log ">>> Connecting + reading chip info..."
  prs info
}

do_erase() {
  log ">>> Mass erasing flash (also removes BLHeli_32 readout protection)..."
  # --allow-erase-all is needed for chips with protection bits set.
  prs erase --allow-erase-all
}

do_flash() {
  log ">>> Flashing bootloader (offset baked into hex: 0x08000000)..."
  prs download --binary-format Hex --verify "$BOOT_HEX"

  log ">>> Flashing AM32 firmware (offset baked into hex: 0x08001000)..."
  prs download --binary-format Hex --verify "$FW_HEX"

  log ">>> Writing default EEPROM at 0x08007C00..."
  prs download --binary-format Bin --base-address 0x08007C00 --verify "$EEPROM_BIN"

  log ">>> Resetting chip..."
  prs reset
}

do_verify() {
  log ">>> Verifying bootloader..."
  prs verify --binary-format Hex "$BOOT_HEX"
  log ">>> Verifying firmware..."
  prs verify --binary-format Hex "$FW_HEX"
}

# ---------------- dispatch ----------------
do_fw_only() {
  log ">>> Reflashing just the firmware at 0x08001000 (no erase, no bootloader)..."
  log ">>> Using firmware: $FW_HEX"
  prs download --binary-format Hex --verify "$FW_HEX"
  log ">>> Resetting chip..."
  prs reset
}

case "$MODE" in
  info-only)
    do_info
    ;;
  erase-only)
    do_erase
    ;;
  verify-only)
    do_verify
    ;;
  fw-only)
    do_fw_only
    ;;
  full)
    do_info
    do_erase
    log ""
    log ">>> Power-cycle the ESC now (unplug bench supply for 2s, plug back in)."
    log ">>> Then press Enter to continue with the flash."
    read -r _
    do_flash
    ;;
  *)
    die "unknown mode: $MODE (use full | info-only | erase-only | verify-only | fw-only)"
    ;;
esac

hr
log "Done. Power-cycle the ESC. If a motor is connected to this MCU's channel,"
log "you should hear the AM32 startup tune (three ascending tones + confirmation)."
log "Log saved to: $LOG"
hr
