# Voron 2.4 350mm — Klipper Configuration

Automated backup of the Klipper printer configuration for a Voron 2.4 350mm CoreXY printer.

## Hardware

| Component | Detail |
|---|---|
| Host | Raspberry Pi 4B (4 GB) |
| Mainboard | BTT Octopus (STM32F446) via USB |
| Toolhead | BTT EBB36 (STM32G0B1) via CAN bus at 1 Mbps |
| Extruder | Clockwork 2 (50:10) |
| Probe | Voron Tap (nozzle contact) |
| Accelerometer | ADXL345 on EBB36 |
| Camera | Logitech C920 Pro HD |
| LEDs | StealthBurner RGBW Neopixels + WLED case lights (104 LEDs) |

## Software Stack

| Component | Purpose |
|---|---|
| **Klipper** | Firmware host |
| **Moonraker** | API server |
| **Fluidd** | Web UI (port 80 via Nginx) |
| **KlipperScreen** | Touchscreen interface |
| **Crowsnest** | Webcam streaming (camera-streamer + WebRTC) |
| **Moonraker-Timelapse** | Print timelapse generation |
| **Katapult** | CAN bootloader on EBB36 |

## Repository Structure

```
├── printer.cfg                 # Main config — MCUs, steppers, heaters, probe, fans, sensors
├── moonraker.conf              # Moonraker API, update manager, WLED, timelapse
├── crowsnest.conf              # Webcam configuration
├── KlipperScreen.conf          # Touchscreen UI, preheat presets, custom menus
├── timelapse.cfg → (symlink)   # Timelapse macros
├── github-backup.sh            # Automated git commit & push script
├── common/                     # Reusable macros
│   ├── calibrate_pa.cfg        # Pressure advance calibration print
│   ├── cancel_print.cfg        # Cancel override
│   ├── github_backup.cfg       # Shell command for backup macro
│   ├── m600.cfg                # Filament change (M600 → PAUSE)
│   ├── pause.cfg               # Pause with z-hop and park
│   ├── print_end.cfg           # End routine (retract, park, timelapse frame)
│   ├── resume.cfg              # Resume with prime
│   └── startup.cfg             # Boot: auto-backup config, LEDs off
└── voron/                      # Voron-specific macros
    ├── bedfans.cfg             # Automatic bed fan control (slow/fast by temp)
    ├── filament_sensor.cfg     # Disable sensor on boot (enabled in PRINT_START)
    ├── g32.cfg                 # Home + QGL + Home + Centre
    ├── idle_timeout.cfg        # 30 min → SLEEP
    ├── nozzle_scrub.cfg        # Purge bucket & brush macro (350mm)
    ├── print_start.cfg         # Full start sequence
    ├── smarthome.cfg           # HOME_IF_NEEDED conditional homing
    ├── speed_test.cfg           # Diagonal speed test
    ├── stealthburner_leds.cfg  # SB LED status macros
    └── wled_lights.cfg         # WLED case light control
```

## Print Start Sequence

1. Enable filament sensor → heat bed, hold extruder at 150°C (Tap-safe)
2. Conditional home → move to centre at Z50 → wait for bed temp
3. Quad Gantry Level (if not already applied) → re-home Z
4. Adaptive bed mesh
5. Heat extruder to target → begin printing

## Automated Backup

Configs are committed to this repo automatically via two triggers:
- **On every Klipper startup** (1-second delayed gcode)
- **Nightly cron job** (midnight)

Commits include Klipper, Moonraker, and Fluidd version strings.

## Disaster Recovery

See **[DISASTER_RECOVERY.md](DISASTER_RECOVERY.md)** for complete rebuild instructions including OS setup, CAN bus configuration, MCU firmware build settings, and all known gotchas.

## Key Gotchas

- **TRSYNC_TIMEOUT:** CAN bus requires `TRSYNC_TIMEOUT = 0.05` in `~/klipper/klippy/mcu.py` (default 0.025). **Overwritten on every Klipper update.**
- **Octopus 12 MHz crystal:** Must select 12 MHz (not default 8 MHz) in `make menuconfig` for the Octopus MCU.
- **gcode_shell_command:** Third-party extension, not in stock Klipper. Must reinstall after fresh Klipper clone.
- **Filament sensor:** Disabled on boot, enabled in PRINT_START. Don't forget this in custom start macros.
- **Bed heater max power:** Capped at 60% (`max_power: 0.6`).
