# AM32 for GEPRC TAKER H65_8S_32Bit 65A 4IN1

Flash AM32 onto the GEPRC TAKER H65_8S_32Bit 65A 4IN1 ESC (the one in the TAKER H743 BT 32Bit 65A stack and on MOZ7 long-range frames) using an ST-Link V2 + `probe-rs` on macOS.

The official `AM32_GEPRC_4IN1_F421` target doesn't match this board's actual pin routing. This repo contains a tested, working flash workflow plus the hex files you need, while a fix gets merged upstream.

See the [upstream issue](https://github.com/am32-firmware/AM32/issues/367) for the diagnosis.

## What you need

- GEPRC TAKER H65_8S_32Bit 65A 4IN1 ESC (4x AT32F421K8U7 MCUs)
- ST-Link V2 (or clone, or any CMSIS-DAP probe)
- macOS with [probe-rs](https://probe.rs) installed: `brew install probe-rs/probe-rs/probe-rs`
- Soldering iron with fine SMD tip (the board does not expose SWD pads, you have to fly-solder onto the AT32F421 pin pads)
- Bench power supply for the ESC (any 4-25 V supply works for MCU power, current limit can be very low since you only need to power the BEC)
- Motors soldered onto the ESC (so you can hear the AM32 startup tone per channel)

## What's in here

```
flash_am32.sh                              driver script around probe-rs
firmware/
  AM32_F421_BOOTLOADER_PB4_V17.hex         AM32 bootloader, PB4 input (use this one)
  AM32_F421_BOOTLOADER_PA2_V17.hex         AM32 bootloader, PA2 input (does not work on this board)
  AM32_F421_BOOTLOADER_PA0_V17.hex         alternate
  AM32_F421_BOOTLOADER_PA15_V17.hex        alternate
  AM32_AT32DEV_F421_2.20.hex               AM32 firmware, PB4 + 045 phase routing (use this one)
  AM32_GEPRC_4IN1_F421_2.20.hex            AM32 firmware, PA2 + 540 (does not work on this board, kept for reference)
  eeprom_version_1_7c00.bin                default EEPROM
```

## How to flash one MCU

Fly-solder four wires to the AT32F421 chip pins for SWDIO (PA13), SWCLK (PA14), 3V3, and GND. Connect those to the ST-Link's matching pins. Power the ESC's BAT/GND from the bench supply.

```bash
./flash_am32.sh PB4
```

That runs a full sequence: chip info, erase (also removes BLHeli_32 readout protection), pauses for a power-cycle, then writes the bootloader, firmware, and default EEPROM. Takes about a minute.

Power-cycle the ESC. The motor wired to this channel plays the AM32 startup tone if all went well.

Repeat on the other three MCUs.

After all four are flashed, plug the FC into your Mac, open [AM32 Configurator](https://am32.ca/configurator), and use Betaflight passthrough to confirm all four ESCs read as `AT32PB4` v2.20. Set motor direction per channel as needed for your prop layout.

## Script modes

```bash
./flash_am32.sh PB4 info-only       # just connect + read chip info
./flash_am32.sh PB4 erase-only      # mass-erase
./flash_am32.sh PB4 verify-only     # compare flash contents against local hex files
./flash_am32.sh PB4 fw-only         # rewrite only firmware at 0x08001000, no erase/bootloader
./flash_am32.sh PB4                 # full flash (default)
```

To use a different firmware file:

```bash
FW=AM32_OTHER_F421_2.20.hex ./flash_am32.sh PB4 fw-only
```

## Memory layout

```
0x08000000  bootloader (4 KB)
0x08001000  firmware   (27 KB)
0x08007C00  default EEPROM (1 KB)
0x08008000  end of AM32 footprint
```

## Why the official target doesn't fit

The pre-built `AM32_GEPRC_4IN1_F421` target uses `HARDWARE_GROUP_AT_E` (PA2 input pin) and `HARDWARE_GROUP_AT_540` (phase comparator order A=PA5, B=PA4, C=PA0). The TAKER H65 actually has its signal trace on the MCU's PB4 pin and uses phase order A=PA0, B=PA4, C=PA5 (`HARDWARE_GROUP_AT_B` + `HARDWARE_GROUP_AT_045`).

The combination of `AT_B` + `AT_045` already exists in AM32 as the generic `AT32DEV_F421` target, which is why we use that hex file here.

Upstream fix is being tracked at [am32-firmware/AM32 issue TBD](https://github.com/am32-firmware/AM32/issues/<NUM>).

## License

MIT. See [LICENSE](LICENSE).

The bootloader, firmware, and EEPROM binaries are copies from [am32-firmware/AM32](https://github.com/am32-firmware/AM32) and [am32-firmware/AM32-bootloader](https://github.com/am32-firmware/AM32-bootloader), distributed under their respective licenses.
