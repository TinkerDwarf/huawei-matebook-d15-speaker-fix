# Huawei MateBook D15 — Speaker/Headphone Auto-Switch Fix for Linux

Fixes simultaneous audio output from both speakers and headphones on Huawei MateBook D15 (BOD-WXX9) running Linux. After applying this fix, speakers mute automatically when headphones are plugged in, and **restore correctly when headphones are unplugged** — no reboot required.

## Affected Hardware

| Field | Value |
|-------|-------|
| Laptop | Huawei MateBook D15 |
| Board | BOD-WXX9-PCB-B4 |
| Tested OS | Ubuntu 24.04 LTS, kernel 6.17.0-23-generic |
| Audio codec | Everest Semi ES8336 (ACPI: ESSX8336) |
| Speaker amp | Huawei custom HWSP0001 (no Linux driver) |

May also work on other MateBook models with HWSP0001 — see [Compatibility](#compatibility).

## The Problem

Linux has no driver for the `HWSP0001` speaker amplifier. The BIOS initializes it once at boot via SMM (before the OS loads), but there is no mechanism in Linux to:
- Mute the speakers when headphones are plugged in
- Re-initialize the amp after it's been powered off

The standard ALSA/DAPM controls, WirePlumber routing, and GPIO tweaks from the `snd_soc_sof_es8336` driver all fail because they don't control the actual amplifier chip.

## How It Works

Through DSDT analysis and I2C register dumping, we identified:

- The speaker amp (`HWSP0001`) sits on **I2C bus 2** at addresses **0x58** (L) and **0x5B** (R), running at 400kHz
- **GPIO 267** on `gpiochip0` is the amp enable pin
- After a GPIO power cycle (`0 → 1`), the amp comes back alive on I2C but in a default (silent) state
- Writing back the 27 BIOS-initialized register values via `i2cset` fully restores the amp

The fix is a `systemd` service that:
1. Monitors the ALSA Headphone Jack control via `alsactl monitor`
2. Sets GPIO 267 low when headphones are inserted (amp off)
3. Sets GPIO 267 high when headphones are removed (amp on), then replays the I2C register initialization

```
Jack event detected
        │
   jack=on  ──→ gpio=0  (amp OFF, headphones active)
   jack=off ──→ gpio=1  (amp ON)
                    │
                    ▼
             i2cset replay
         27 registers → 0x58 & 0x5B
                    │
                    ▼
           Speakers working ✓
```

## Requirements

```bash
sudo apt install i2c-tools gpiod alsa-utils
```

## Installation

```bash
git clone https://github.com/TinkerDwarf/huawei-matebook-d15-speaker-fix
cd huawei-matebook-d15-speaker-fix
sudo bash install.sh
```

That's it. The service starts immediately and enables on boot.

## Manual Installation

```bash
sudo cp huawei-speaker-mute.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/huawei-speaker-mute.sh
sudo cp huawei-speaker-mute.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now huawei-speaker-mute.service
```

## Verifying It Works

```bash
sudo systemctl status huawei-speaker-mute.service
```

Plug in headphones → speakers should go silent.  
Unplug headphones → speakers should come back within ~0.5 seconds.

## Compatibility

This fix was developed and tested on **BOD-WXX9-PCB-B4**. It may work on other MateBook models that use the same `HWSP0001` amplifier.

To check if your board has `HWSP0001`:
```bash
ls /sys/bus/acpi/devices/ | grep -i hw
# Should show: HWSP0001:00
```

To check if the amp is on I2C bus 2 at the same addresses:
```bash
readlink -f /sys/bus/i2c/devices/i2c-HWSP0001:00
# Should contain: i2c_designware.2/i2c-2
```

If your board uses different GPIO or I2C bus numbers, edit the variables at the top of `huawei-speaker-mute.sh`:

```bash
GPIOCHIP=gpiochip0
LINE=267          # GPIO line for amp enable
JACK_NUMID=27     # ALSA control numid for Headphone Jack
I2C_BUS=2         # I2C bus number
```

**If your register values differ:** the I2C register values in the script are specific to BOD-WXX9. If your amp has a different initialization state, you'll need to dump your own registers right after a fresh boot (before plugging in headphones):

```bash
sudo i2cdump -y -f 2 0x58 > amp_0x58_init.txt
sudo i2cdump -y -f 2 0x5B > amp_0x5B_init.txt
```

Then update the `reinit_amp()` function accordingly. Feel free to open an issue with your dump and board info.

## Technical Details

### DSDT Analysis

The HWSP0001 device in ACPI (`\_SB_.PC00.I2C3.HWSP`):
- Two I2C resources: 0x58 and 0x5B at 400kHz on I2C3
- GPIO enable pin decoded via `GNUM(0x090B000B)` → gpio-267
- `_INI` method only sets the GPIO pin number in the resource template — it does **not** initialize the amp over I2C

The actual I2C initialization happens in BIOS firmware (SMM) before Linux boots. There is no ACPI method that triggers it.

### Why acpi_call Doesn't Help

After installing `acpi-call-dkms` and inspecting the DSDT, the `_INI` method for HWSP0001 is:
```c
Method (_INI, 0, NotSerialized) {
    PIN1 = GNUM(0x090B000B)  // just writes gpio number into resource template
}
```
No I2C writes. The real init is in BIOS SMM code.

### Register Differences (BIOS init vs default state)

| Register | BIOS value | Default (after power cycle) |
|----------|-----------|---------------------------|
| 0x01 | 0x69 | 0x38 |
| 0x03 | 0x16 | 0x0c |
| 0x04 | 0x80 | 0x00 |
| 0x05 | 0x0c | 0x08 |
| 0x06 | 0x11 | 0x10 |
| 0x07 | 0x93 | 0x43 |
| 0x09 | 0x0b | 0x03 |
| 0x0b | 0x4b | 0x4a |
| 0x0c | 0x00 | 0x03 |
| 0x0d | 0x77 | 0xdd |
| 0x0f | 0x51 | 0x23 |
| 0x10 | 0x58 | 0x08 |
| 0x58 | 0x00 | 0x80 |
| 0x59 | 0x80 | 0x00 |
| 0x61–0x69 | see script | different |
| 0x71–0x74 | see script | different |

## Known Limitations

- The exact chip model behind HWSP0001 is unknown (likely TI TAS25xx or similar). Without a datasheet, we don't know the meaning of each register.
- The register values were captured from one specific board. If your board was manufactured at a different revision or calibrated differently, values may differ.
- The `snd_soc_sof_es8336` DMI quirk patch for BOD-WXX9 (included in some versions of this repo) activates DAPM speaker switching but has no effect on actual sound output — the real amp is HWSP0001, not controlled by the codec driver.

## Contributing

If you have a different MateBook model with HWSP0001, please open an issue with:
- Board model (`cat /sys/class/dmi/id/board_name`)
- Output of `readlink -f /sys/bus/i2c/devices/i2c-HWSP0001:00`
- Your amp register dump (fresh boot, before any jack events)
- GPIO number (from `cat /sys/bus/acpi/devices/HWSP0001:00/path` + DSDT analysis)

## License

MIT
