# Voron 2.4 350mm — Klipper Configuration

Automated backup of the Klipper printer configuration for a Voron 2.4 350mm CoreXY 3D printer.

---

## About This Printer

The [Voron 2.4](https://vorondesign.com/voron2.4) is a fully enclosed, high-performance CoreXY 3D printer designed by the Voron Design community for self-sourcing and self-assembly. The 350mm variant has a 350×350×340mm build volume. It uses a fixed bed with a flying gantry levelled via four independent Z motors (Quad Gantry Level), and is optimised for printing engineering materials such as ABS and ASA at elevated chamber temperatures.

This specific build is **serial number V2.3902**, built and maintained by Lee. It has been significantly modified from the stock build — see [Hardware Mods](#hardware-mods) below.

---

## Hardware

| Component | Detail |
|---|---|
| Host | Raspberry Pi 4B (4 GB) |
| Mainboard | BTT Octopus (STM32F446) via USB |
| Toolhead Board | BTT EBB36 (STM32G0B1) via CAN bus at 1 Mbps |
| Extruder | Clockwork 2 (50:10 gear ratio) |
| Hotend | Dragon V6 (high-flow, all-metal) |
| Build Plate | LDO DarkRock 355mm textured PEI flex plate |
| Probe | Chaoticlabs CNC Tap V2 (nozzle contact, magnetic flexure) |
| Accelerometer | ADXL345 on EBB36 |
| Touchscreen | 4.3" Waveshare DSI LCD (KlipperScreen) |

---

## Software Stack

| Component | Purpose |
|---|---|
| **Klipper** | Printer firmware host — runs on the Pi, controls all MCUs |
| **Moonraker** | REST API server — bridges Klipper to web interfaces and integrations |
| **Fluidd** | Web UI (port 80 via Nginx) |
| **KlipperScreen** | Touchscreen interface on the 4.3" DSI display |
| **Crowsnest** | Webcam streaming (camera-streamer + WebRTC) |
| **Moonraker-Timelapse** | Per-print timelapse generation |
| **Katapult** | CAN bootloader on EBB36 for over-the-wire firmware flashing |
| **WLED** | LED controller firmware on internal ESP8266 — 8-preset status lighting |
| **Claude (Anthropic)** | AI print monitoring — analyses webcam feed for failures, anomalies, and print quality in a dedicated LXC container on the Proxmox host |

---

## Hardware Mods

### Toolhead & Motion

| Mod | Description |
|---|---|
| [Chaoticlabs CNC Tap V2](https://github.com/chaoticlabs/CNC_Tap) | Nozzle-contact probing with a magnetic flexure (more durable than Voron Tap's printed flexure) — the nozzle itself is the probe. Z offset behaviour matches Voron Tap: `Z_OFFSET_APPLY_PROBE` is broken, see known bugs below |
| [Stealthburner](https://github.com/VoronDesign/Voron-Stealthburner) | Replacement printhead with integrated RGBW LED status lighting and improved part cooling |
| [Clockwork 2](https://github.com/VoronDesign/Voron-Stealthburner) | Direct-drive extruder integrated into the Stealthburner carriage (50:10 gear ratio) |
| [Titanium Gantry Backers](https://mods.vorondesign.com/) | Titanium extrusion backers on the X/Y gantry rails to counteract thermal expansion and maintain gantry geometry at elevated chamber temps |
| [GE5C Z Joint Bearings](https://mods.vorondesign.com/details/eB5T2RNQcYI4o6cilhpXEg) | Spherical GE5C bearings at the gantry Z joints (by hartk1213) — eliminates binding and improves QGL repeatability |

### Bed & Chamber

| Mod | Description |
|---|---|
| [Bed Fans](https://mods.vorondesign.com/details/28xgztUufAtAfV4XUL5l4w) | Bed-mounted fans (by Ellis) for active chamber heating — circulate hot air from the bed heater to reach chamber temp faster |
| [Nozzle Brush & Purge Bucket](https://github.com/VoronDesign/VoronUsers/tree/master/printer_mods/edwardyeeks/Decontaminator_Purge_Bucket_%26_Nozzle_Scrubber) | Purge bucket and silicone brush for nozzle cleaning before probing and printing |
| [Exhaust Cover](https://github.com/LeeHeap/Voron-V2.4-Mods/tree/main/Exhaust%20Cover) | Replaces the stock exhaust housing with a clean blanking plate including a threaded insert for a bowden tube passthrough — retains chamber heat while allowing rear filament routing (custom mod) |

### Panels & Access

| Mod | Description |
|---|---|
| [Removable Doors](https://mods.vorondesign.com/details/WqhhKrXksAZ4omhHS1RY4Q) | Tool-free magnetic removable front doors (by ElPoPo) |
| [Removable Panels](https://www.printables.com/model/702768-kit-for-removable-panelsdoors-for-voron-v2trident-) | Full kit for tool-free removable side and top panels (by VictorMateusO) |
| [Deck Panel Support Clips](https://mods.vorondesign.com/details/aBGbXOxS452m5bKCS7hWlw) | Reinforcement clips for the deck panel (by wile-e1) — prevents flex and rattle |
| [Hidden Cable Routing Z Belt Covers](https://mods.vorondesign.com/details/LzEFU0RDHXUarF7y69x2Q) | Replaces stock Z belt covers with versions that integrate cable routing channels (by Akio) |
| 2020 Profile Covers | Snap-on covers for exposed aluminium extrusion ends — cosmetic and safety |

### Electronics & Sensing

| Mod | Description |
|---|---|
| [BTT EBB36 CAN Toolboard](https://github.com/bigtreetech/EBB) | CAN bus toolhead board — reduces umbilical wiring to a single 4-wire cable carrying power and CAN data |
| Internal ESP8266 (WLED) | ESP8266 running WLED firmware for addressable LED control — 8 print-status presets (idle, heating, printing, homing, etc.) |
| [Top-Mounted LED Corner Strips](https://github.com/LeeHeap/Voron-V2.4-Mods/tree/main/LED%20Corners) | Redesigned 15.5mm quarter-round corner mounts for WS2812B+ LED strips — adds optional Voron logo insert, cable passthrough from top to vertical extrusion, and R2 idler compatibility (custom mod) |
| [Skirt Buttons](https://github.com/LeeHeap/Voron-V2.4-Mods/tree/main/Skirt%20Buttons) | Microswitch button enclosures that mount in the Voron skirt — snap-fit, no extra hardware, used for Klipper macro triggers and lighting control (custom mod) |
| [4.3" Waveshare DSI Touchscreen](https://www.waveshare.com/4.3inch-dsi-lcd.htm) | DSI-connected touchscreen displaying KlipperScreen — mounted on the rear of the printer |
| Internal Logitech C920 Webcam | Top-mounted USB webcam for print monitoring and timelapse |
| Internal Arducam IMX179 Webcam | Rear-mounted 8MP USB webcam (port 8081) for a second monitoring angle |
| Rear Filament Runout Sensor | Switch-based filament sensor — triggers M600 filament change on runout |

---

## Automated Backup

Configs are committed to this repo automatically via two triggers:
- **On every Klipper startup** (1-second delayed gcode in `common/startup.cfg`)
- **Nightly cron job** at 00:00 in lee's crontab (not root's)

Commits include Klipper, Moonraker, and Fluidd version strings in the commit message. The script at `scripts/github-backup.sh` uses absolute paths only, exports `HOME=/home/lee` explicitly, and writes a status summary to `/tmp/github-backup-status` after each run.

If pushes start failing silently, the first thing to check is ownership of `/home/lee/.git-credentials`: it must be `lee:lee` with mode `0600`. If an earlier root-as-lee `git push` touched it, ownership flips to root and every subsequent push fails with "could not read Username for 'https://github.com'".

---

## Known Issues

### Z_OFFSET_APPLY_PROBE is broken with Tap-style probes (Voron Tap and CNC Tap)

Klipper's built-in `Z_OFFSET_APPLY_PROBE` applies baby-step adjustments with the **wrong sign** when the nozzle itself is the probe (Voron Tap, CNC Tap, or any similar nozzle-contact design). Use the custom `SAVE_Z_OFFSET` macro instead. See [Z_OFFSET_TAP_BUG.md](Z_OFFSET_TAP_BUG.md) for full explanation and correct workflow.

---

## Repository Structure

```
├── printer.cfg                 # Main config — MCUs, steppers, heaters, probe, fans, sensors
├── moonraker.conf              # Moonraker API, update manager, WLED, timelapse
├── crowsnest.conf              # Webcam configuration
├── KlipperScreen.conf          # Touchscreen UI, preheat presets, custom menus
├── timelapse.cfg → (symlink)   # Timelapse macros
├── scripts/
│   └── github-backup.sh        # Automated git commit & push script
├── common/                     # Reusable macros (auto-included via printer.cfg wildcard)
│   ├── calibrate_pa.cfg        # Pressure advance calibration print
│   ├── cancel_print.cfg        # Cancel override (keeps bed hot for quick restart)
│   ├── filament_change.cfg     # Filament change workflow helper
│   ├── github_backup.cfg       # gcode_shell_command wrapper + BACKUP_CONFIG macro
│   ├── m600.cfg                # Filament change (M600 triggers PAUSE)
│   ├── pause.cfg               # Pause with z-hop and park
│   ├── print_end.cfg           # End routine (retract, park, timelapse frame)
│   ├── resume.cfg              # Resume with prime
│   ├── save_z_offset.cfg       # Tap-safe SAVE_Z_OFFSET (see Known Issues)
│   ├── startup.cfg             # Boot: delayed backup trigger, LEDs off
│   └── virtual_tools.cfg       # T0-T9 virtual extruders for multi-colour printing
└── voron/                      # Voron-specific macros and hardware configs
    ├── bedfans.cfg             # Automatic bed fan control (off during print to prevent ABS warp)
    ├── c920.cfg                # Logitech C920 webcam-specific settings
    ├── filament_sensor.cfg     # Disable sensor on boot (enabled in PRINT_START)
    ├── g32.cfg                 # Home + QGL + Home + Centre
    ├── idle_timeout.cfg        # 30 min -> SLEEP
    ├── nozzle_scrub.cfg        # Purge bucket & brush macro (350mm)
    ├── print_monitor.cfg       # AI print monitoring hooks (Claude LXC integration)
    ├── print_start.cfg         # Full start sequence (conditional QGL, adaptive mesh)
    ├── smarthome.cfg           # HOME_IF_NEEDED conditional homing
    ├── speed_test.cfg          # Diagonal speed test
    ├── stealthburner_leds.cfg  # SB LED status macros
    └── wled_lights.cfg         # WLED case light control
```

---

## Disaster Recovery

See **[DISASTER_RECOVERY.md](DISASTER_RECOVERY.md)** for complete rebuild instructions including OS setup, CAN bus configuration, MCU firmware build settings, and all known gotchas.
