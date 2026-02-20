# Voron 2.4 350mm — Disaster Recovery & System Documentation

> **Last audited:** 2026-02-19  
> **Hostname:** `voron` • **IP:** `<PRINTER_IP>` (WiFi/DHCP)  
> **Repository:** [<GITHUB_USER>/Klipper-config](https://github.com/<GITHUB_USER>/Klipper-config)

---

## Table of Contents

1. [Hardware Overview](#1-hardware-overview)
2. [Operating System](#2-operating-system)
3. [Network & Connectivity](#3-network--connectivity)
4. [Software Stack & Versions](#4-software-stack--versions)
5. [Systemd Services](#5-systemd-services)
6. [MCU Firmware](#6-mcu-firmware)
7. [Klipper Configuration Deep-Dive](#7-klipper-configuration-deep-dive)
8. [Moonraker Configuration](#8-moonraker-configuration)
9. [Web Interface (Fluidd + Nginx)](#9-web-interface-fluidd--nginx)
10. [Webcam (Crowsnest)](#10-webcam-crowsnest)
11. [KlipperScreen](#11-klipperscreen)
12. [Timelapse](#12-timelapse)
13. [WLED Case Lighting](#13-wled-case-lighting)
14. [Automated GitHub Backup](#14-automated-github-backup)
15. [Known Gotchas & Workarounds](#15-known-gotchas--workarounds)
16. [Disaster Recovery Steps](#16-disaster-recovery-steps)

---

## 1. Hardware Overview

### Host Computer

| Component | Detail |
|---|---|
| **Board** | Raspberry Pi 4 Model B Rev 1.4 |
| **RAM** | 4 GB |
| **Storage** | 64 GB microSD (12 GB used / 43 GB free) |
| **Architecture** | aarch64 (64-bit) |
| **Kernel** | 6.1.21-v8+ |

### Printer Hardware

| Component | Detail |
|---|---|
| **Printer** | Voron 2.4 350mm (CoreXY) |
| **Mainboard** | BigTreeTech Octopus (STM32F446, 12 MHz crystal) |
| **Toolhead Board** | BTT EBB36 v1.2 (STM32G0B1, CAN bus) |
| **CAN Adapter** | Geschwister Schneider CAN adapter (gs_usb — `1d50:606f`) |
| **Extruder** | Clockwork 2 (gear ratio 50:10) |
| **Hotend Sensor** | Generic 3950 thermistor |
| **Bed Sensor** | Generic 3950 thermistor |
| **Probe** | Voron Tap (nozzle probe, `probe:z_virtual_endstop`) |
| **Accelerometer** | ADXL345 on EBB36 (SPI) |
| **Webcam** | Logitech C920 Pro HD (USB, `046d:08e5`) |
| **LEDs** | StealthBurner RGBW Neopixels (3-chain) on EBB36 |
| **Case Lighting** | WLED controller at `<WLED_IP>` (104 LED chain) |
| **Filament Sensor** | Switch sensor on `PG12` (Octopus) |

### Stepper Motors (all TMC2209 UART)

| Axis | Octopus Port | Run Current | Microsteps | Notes |
|---|---|---|---|---|
| X (B motor, left) | MOTOR_0 (`PF13`) | 1.1A | 16 | 400 steps/rev, stealthchop off |
| Y (A motor, right) | MOTOR_1 (`PG0`) | 1.1A | 16 | 400 steps/rev, stealthchop off |
| Z0 (front left) | MOTOR_2 (`PF11`) | 1.0A | 16 | 80:16 gear ratio |
| Z1 (rear left) | MOTOR_3 (`PG4`) | 1.0A | 16 | 80:16 gear ratio |
| Z2 (rear right) | MOTOR_4 (`PF9`) | 1.0A | 16 | 80:16 gear ratio |
| Z3 (front right) | MOTOR_5 (`PC13`) | 1.0A | 16 | 80:16 gear ratio |
| Extruder | EBB36 (`PD0`) | 0.6A | 16 | CW2 50:10 gear ratio |

### Fan Configuration

| Fan | Pin | Type | Notes |
|---|---|---|---|
| Part Cooling (FAN0) | `ebbcan:PA0` | Standard | off_below: 0.10 |
| Hotend (FAN1) | `ebbcan:PA1` | Heater fan | Activates at 50°C |
| Controller | `PD12` | Controller fan | 50% speed, tied to bed heater |
| Exhaust (FAN3) | `PD13` | Heater fan | 50% speed, activates at 60°C bed temp |
| Bed Fans | `PD14` | Generic fan | Macro-controlled (slow/fast/off) |

---

## 2. Operating System

| Property | Value |
|---|---|
| **Distribution** | Raspbian GNU/Linux 11 (Bullseye) |
| **Architecture** | aarch64 |
| **Kernel** | 6.1.21-v8+ (2023-04-03) |
| **Python** | 3.9.2 (system) |
| **Node.js** | v20.18.1 |
| **npm** | 10.8.2 |
| **Timezone** | Europe/London (GMT) |
| **NTP** | Active, synchronized |
| **User** | `<USER>` (primary user, runs all Klipper services) |
| **Swap** | 256 MB |

### Key `/boot/config.txt` Settings

```ini
dtparam=spi=on           # SPI enabled (for ADXL, displays)
enable_uart=1             # UART enabled
dtoverlay=disable-bt      # Bluetooth disabled (frees UART)
dtparam=i2c_arm=on        # I2C enabled
gpu_mem=256               # GPU memory allocation (all Pi variants)
dtoverlay=vc4-kms-v3d     # KMS video driver (for KlipperScreen)
max_framebuffers=2        # Dual framebuffer support
```

> **Gotcha:** Bluetooth is intentionally disabled via `dtoverlay=disable-bt` to free the primary UART for serial communication. Do not re-enable unless you remap serial ports.

---

## 3. Network & Connectivity

### WiFi

| Setting | Value |
|---|---|
| Interface | `wlan0` |
| IP | `<PRINTER_IP>/24` (DHCP) |
| SSID | `<YOUR_SSID>` |
| Security | WPA2-PSK (CCMP) |
| Country | GB |
| Config File | `/etc/wpa_supplicant/wpa_supplicant.conf` |

### CAN Bus

| Setting | Value |
|---|---|
| Interface | `can0` |
| Bitrate | 1,000,000 (1 Mbps) |
| TX Queue Length | 1024 |
| Adapter | gs_usb (Geschwister Schneider USB-CAN) |
| Config File | `/etc/network/interfaces.d/can0` |

**CAN interface configuration** (`/etc/network/interfaces.d/can0`):
```
allow-hotplug can0
iface can0 can static
	bitrate 1000000
	up ifconfig $IFACE txqueuelen 1024
```

The CAN bus is brought up by `ifup@can0.service` automatically on hotplug.

### WiFi Keepalive (Sonar)

Sonar is installed but **disabled by default** in its config (`/home/<USER>/sonar/resources/sonar.conf` → `enable: false`). The systemd service is still active, which means it runs but effectively does nothing unless you edit the config to `enable: true`. Useful if WiFi drops become a problem.

---

## 4. Software Stack & Versions

All software lives under `/home/<USER>/` and runs as user `<USER>`.

| Component | Version | Path | Source |
|---|---|---|---|
| **Klipper** | `v0.13.0-540-g57c2e0c9` | `/home/<USER>/klipper` | [Klipper3d/klipper](https://github.com/Klipper3d/klipper) |
| **Moonraker** | `v0.10.0-8-g293a4cf` | `/home/<USER>/moonraker` | [Arksine/moonraker](https://github.com/Arksine/moonraker) |
| **Fluidd** | `v1.36.2` | `/home/<USER>/fluidd` | [fluidd-core/fluidd](https://github.com/fluidd-core/fluidd) |
| **KlipperScreen** | `v0.4.6-41-g5a5ae382` | `/home/<USER>/KlipperScreen` | [KlipperScreen/KlipperScreen](https://github.com/KlipperScreen/KlipperScreen) |
| **Crowsnest** | `v4.1.17-1-g9cc3d4a` | `/home/<USER>/crowsnest` | [mainsail-crew/crowsnest](https://github.com/mainsail-crew/crowsnest) |
| **Moonraker-Timelapse** | (main branch) | `/home/<USER>/moonraker-timelapse` | [mainsail-crew/moonraker-timelapse](https://github.com/mainsail-crew/moonraker-timelapse) |
| **Katapult** (bootloader) | `v0.0.1-110-gb0bf421` | `/home/<USER>/katapult` | (formerly CanBoot) |
| **KIAUH** | v4.0.0 | `/home/<USER>/kiauh` | [dw-0/kiauh](https://github.com/dw-0/kiauh) |

### Python Virtual Environments

| Environment | Path | Python Version |
|---|---|---|
| Klippy | `/home/<USER>/klippy-env` | 3.9.2 |
| Moonraker | `/home/<USER>/moonraker-env` | 3.9.2 |
| KlipperScreen | `/home/<USER>/.KlipperScreen-env` | 3.9.2 |

### Klipper Extension: gcode_shell_command

Installed at `/home/<USER>/klipper/klippy/extras/gcode_shell_command.py`. This is a third-party extension (from KIAUH) that allows running shell commands from gcode macros. **This is NOT part of stock Klipper** — it must be manually re-installed after a fresh Klipper clone.

It can be sourced from `/home/<USER>/kiauh/kiauh/extensions/gcode_shell_cmd/assets/gcode_shell_command.py`.

---

## 5. Systemd Services

All services run as user `<USER>` and are configured in `/etc/systemd/system/`.

| Service | Description | Status |
|---|---|---|
| `klipper.service` | Klipper firmware host | Active |
| `moonraker.service` | Moonraker API server | Active |
| `crowsnest.service` | Webcam streamer | Active |
| `KlipperScreen.service` | Touchscreen UI | Active |
| `nginx.service` | Web server (Fluidd) | Active |
| `sonar.service` | WiFi keepalive daemon | Active (but internally disabled) |
| `ifup@can0.service` | CAN bus interface | Active |

### Environment Files

These are located at `/home/<USER>/printer_data/systemd/` and define startup arguments:

**`klipper.env`:**
```bash
KLIPPER_ARGS="/home/<USER>/klipper/klippy/klippy.py /home/<USER>/printer_data/config/printer.cfg -I /home/<USER>/printer_data/comms/klippy.serial -l /home/<USER>/printer_data/logs/klippy.log -a /home/<USER>/printer_data/comms/klippy.sock"
```

**`moonraker.env`:**
```bash
MOONRAKER_ARGS="/home/<USER>/moonraker/moonraker/moonraker.py -d /home/<USER>/printer_data"
```

**`crowsnest.env`:**
```bash
CROWSNEST_ARGS="-c /home/<USER>/printer_data/config/crowsnest.conf"
```

---

## 6. MCU Firmware

Both MCUs run Klipper firmware `v0.13.0-540-g57c2e0c9-dirty` built on the Pi itself.

### Octopus Mainboard (MCU `mcu`)

| Setting | Value |
|---|---|
| MCU | STM32F446xx |
| Clock | 180 MHz (12 MHz external crystal) |
| Connection | USB serial (`/dev/serial/by-path/platform-fd500000.pcie-pci-0000:01:00.0-usb-0:1.4:1.0`) |
| Serial ID | `usb-Klipper_stm32f446xx_5E0033000A51373330333137-if00` |
| Restart method | `command` |

**Build settings for Octopus** (`make menuconfig`):
- Micro-controller: STM32 → STM32F446
- Bootloader offset: 32KiB (for stock Octopus bootloader)
- Clock reference: **12 MHz crystal** ⚠️
- Communication: USB (on PA11/PA12)

> **⚠️ CRITICAL GOTCHA — 12 MHz Crystal:** The BTT Octopus uses a **12 MHz** crystal, NOT the 8 MHz default. You MUST select "12 MHz crystal" in `make menuconfig` or the MCU will fail to communicate. This has caused issues during past updates.

**Flashing the Octopus:**
```bash
cd ~/klipper
make menuconfig   # Configure as above
make clean && make
# Method 1: USB DFU (hold BOOT0 button, reset, then:)
make flash FLASH_DEVICE=/dev/serial/by-id/usb-Klipper_stm32f446xx_5E0033000A51373330333137-if00
# Method 2: Copy firmware.bin to SD card, insert into Octopus, power cycle
```

### EBB36 CAN Toolhead (MCU `ebbcan`)

| Setting | Value |
|---|---|
| MCU | STM32G0B1xx |
| Clock | 64 MHz (8 MHz crystal) |
| Connection | CAN bus (`canbus_uuid: 2fd24cc0e083`) |
| Bootloader | Katapult (formerly CanBoot) at `0x8000000`, app at `0x8002000` |
| CAN Pins | PB0/PB1 |
| CAN Frequency | 1,000,000 (1 Mbps) |

**Build settings for EBB36** (`make menuconfig`):
- Micro-controller: STM32 → STM32G0B1
- Bootloader offset: **8KiB** (Katapult)
- Clock reference: 8 MHz crystal
- Communication: CAN bus (on PB0/PB1)
- CAN bus speed: 1000000

> **Note:** The current `~/klipper/.config` file contains the EBB36 config (the last firmware built). When switching between MCU builds, always run `make menuconfig` afresh.

**Flashing the EBB36 via Katapult over CAN:**
```bash
cd ~/klipper
make menuconfig   # Configure as above
make clean && make
# Flash over CAN using Katapult:
python3 ~/katapult/scripts/flashtool.py -i can0 -u 2fd24cc0e083 -f ~/klipper/out/klipper.bin
```

### Katapult Bootloader (on EBB36)

Katapult is installed on the EBB36 as a CAN bootloader. Its config matches the EBB36 settings (STM32G0B1, 8KiB offset, CAN on PB0/PB1, 1 Mbps). The bootloader lives in the first 8 KiB of flash and hands off to Klipper at `0x8002000`.

**Rebuilding Katapult** (rarely needed):
```bash
cd ~/katapult
make menuconfig   # Same MCU/CAN settings as above
make clean && make
# Flash via DFU or existing bootloader
```

---

## 7. Klipper Configuration Deep-Dive

Configuration is stored at `/home/<USER>/printer_data/config/` and version-controlled via Git.

### File Structure

```
printer_data/config/
├── printer.cfg              # Main config (includes everything, stepper/heater/probe definitions)
├── moonraker.conf           # Moonraker API server config
├── crowsnest.conf           # Webcam streaming config
├── KlipperScreen.conf       # Touchscreen UI config
├── timelapse.cfg → ~/moonraker-timelapse/klipper_macro/timelapse.cfg  (symlink)
├── github-backup.sh         # Automated git backup script
├── .gitignore               # Ignores *.bkp files
├── common/                  # Reusable macros (not printer-specific)
│   ├── calibrate_pa.cfg     # Pressure advance calibration print macro
│   ├── cancel_print.cfg     # CANCEL_PRINT override
│   ├── github_backup.cfg    # gcode_shell_command for backup
│   ├── m600.cfg             # M600 filament change → PAUSE
│   ├── pause.cfg            # PAUSE macro (z-hop, park at front)
│   ├── print_end.cfg        # PRINT_END macro (retract, park, timelapse frame)
│   ├── resume.cfg           # RESUME macro (restore position, prime)
│   └── startup.cfg          # Delayed gcode: auto-backup + STATUS_OFF on boot
└── voron/                   # Voron-specific macros and configs
    ├── bedfans.cfg          # Bed fan speed control (slow while heating, fast at temp)
    ├── c920.cfg             # C920 camera controls (currently all commented out)
    ├── filament_sensor.cfg  # Disables filament sensor on startup
    ├── g32.cfg              # G32 macro: Home → QGL → Home → Centre
    ├── idle_timeout.cfg     # 30min timeout → SLEEP (unless paused)
    ├── nozzle_scrub.cfg     # Nozzle brush/purge bucket macro (350mm config)
    ├── print_start.cfg      # PRINT_START macro (full sequence)
    ├── smarthome.cfg        # HOME_IF_NEEDED conditional homing
    ├── speed_test.cfg       # Fast diagonal speed test macro
    ├── stealthburner_leds.cfg # SB LED status macros (GRBW Neopixels)
    ├── wled_lights.cfg      # WLED case light control via Moonraker
    └── scripts/
        └── c920_disable_autofocus.sh  # v4l2-ctl autofocus disable script
```

### Motion System Settings

```
Kinematics: CoreXY
Max velocity: 500 mm/s
Max acceleration: 10,000 mm/s²
Max Z velocity: 30 mm/s
Max Z acceleration: 350 mm/s²
Square corner velocity: 5.0 mm/s
```

### Input Shaper

```
X axis: 3hump_ei @ 80.2 Hz
Y axis: mzv @ 35.2 Hz
```

Shaper calibration graphs are stored at `voron/shaper_calibrate_x.png` and `voron/shaper_calibrate_y.png`.

### Probe (Voron Tap)

- Uses nozzle as probe (no X/Y offset)
- Z offset: **-1.400** (saved in SAVE_CONFIG section)
- 3 samples, median result, 0.05 tolerance, 3 retries
- **Activate gcode** lowers extruder temp to 150°C before probing (prevents filament ooze affecting readings)
- Higher negative z_offset = nozzle closer to bed

### Bed Mesh

```
Speed: 300 mm/s
Mesh area: 15,15 → 335,335
Probe count: 6×6
Algorithm: Bicubic
Fade: 0.6 → 10.0
Zero reference: 175,175 (bed centre)
```

### Quad Gantry Level

```
Speed: 350 mm/s
Points: 25,25 / 25,325 / 325,325 / 325,25
Retries: 5
Tolerance: 0.0075 mm
Max adjust: 10 mm
```

### PRINT_START Sequence

The `PRINT_START` macro (called by the slicer with `BED` and `EXTRUDER` params) follows this sequence:

1. Enable filament sensor
2. Heat bed to target, hold extruder at 150°C (Tap-safe probing temp)
3. `HOME_IF_NEEDED` — conditional homing
4. Move to bed centre at Z50
5. Wait for bed temperature
6. If QGL not already applied → run `QUAD_GANTRY_LEVEL` → re-home Z
7. Run adaptive bed mesh (`BED_MESH_CALIBRATE ADAPTIVE=1`)
8. Heat extruder to target temperature
9. Reset extruder, begin printing

### PRINT_END Sequence

1. Disable filament sensor
2. Retract 3mm, z-hop 40mm
3. Move to remove stringing
4. Turn off heaters and part fan
5. Park at rear centre (`X175 Y350`)
6. Take timelapse frame
7. Disable steppers

### PID Values (Auto-tuned, in SAVE_CONFIG)

```
Extruder: Kp=30.557, Ki=1.959, Kd=119.173
Bed:      Kp=38.678, Ki=1.417, Kd=263.975
```

### Bed Fan Control

The `bedfans.cfg` macro overrides `M140`, `M190`, `SET_HEATER_TEMPERATURE`, and `TURN_OFF_HEATERS` to automatically manage bed fans:

- **Threshold:** 90°C bed target
- **Below threshold:** Fans off
- **Heating above threshold:** Slow speed (0.2)
- **At temperature:** Fast speed (0.6)
- Monitoring loop checks every 5 seconds until target reached

### Idle Timeout

Set to 1800 seconds (30 minutes). If paused, timeout is suppressed. Otherwise triggers `SLEEP` (motors off, fans off, heaters off, LEDs off).

### Filament Sensor

Switch sensor on `PG12` with `pause_on_runout: True`. **Disabled on startup** via delayed gcode (`filament_sensor.cfg`), then re-enabled in `PRINT_START`. This prevents false triggers during loading/unloading.

---

## 8. Moonraker Configuration

Config file: `/home/<USER>/printer_data/config/moonraker.conf`

### Key Sections

| Section | Purpose |
|---|---|
| `[server]` | Listens on `0.0.0.0:7125` |
| `[authorization]` | Trusts `10.0.0.0/8` and common private ranges |
| `[octoprint_compat]` | OctoPrint API compatibility (for slicer upload) |
| `[history]` | Print history tracking |
| `[timelapse]` | Timelapse integration (default settings) |
| `[analysis]` | Gcode analysis for time estimates |
| `[wled lights]` | WLED integration at `<WLED_IP>` (104 LEDs, HTTP) |
| `[power printer_lights]` | Moonraker power device linked to `SET_CASELIGHTS` macro |

### Update Manager Entries

Moonraker manages updates for: KlipperScreen, Fluidd, Crowsnest, and Timelapse. The update channel is set to `dev` with a 168-hour (7-day) refresh interval.

### Webcam Configuration

Defined in `moonraker.conf` under `[webcam Voron]`:
- Service: `mjpegstreamer-adaptive`
- Target FPS: 15
- Stream URL: `/webcam/?action=stream`
- Aspect ratio: 4:3

---

## 9. Web Interface (Fluidd + Nginx)

### Fluidd

- Version: `v1.36.2`
- Path: `/home/<USER>/fluidd`
- Served by Nginx on port 80

### Nginx Configuration

- Site config: `/etc/nginx/sites-enabled/fluidd` (symlinked from `sites-available`)
- Upstream config: `/etc/nginx/conf.d/upstreams.conf`
- Proxies API requests to Moonraker at `127.0.0.1:7125`
- Proxies webcam streams from ports 8080-8083
- Gzip compression enabled
- No upload size limit (`client_max_body_size 0`)

---

## 10. Webcam (Crowsnest)

Config file: `/home/<USER>/printer_data/config/crowsnest.conf`

| Setting | Value |
|---|---|
| Mode | `camera-streamer` (WebRTC + MJPEG) |
| RTSP | Enabled on port 8554 |
| HTTP Port | 8080 |
| Device | `/dev/v4l/by-id/usb-046d_HD_Pro_Webcam_C920-video-index0` |
| Resolution | 1920×1080 |
| Max FPS | 30 |

### Camera Script

A C920 autofocus disable script exists at `voron/scripts/c920_disable_autofocus.sh`. It uses `v4l2-ctl` to set `focus_auto=0` and `focus_absolute=30`. The corresponding gcode macros for zoom/pan control in `c920.cfg` are currently **all commented out** (they depended on `gcode_shell_command` which was previously missing).

---

## 11. KlipperScreen

Config file: `/home/<USER>/printer_data/config/KlipperScreen.conf`

### General Settings

- Move speed XY: 150 mm/s, Z: 30 mm/s
- Print estimate: slicer-based
- Screen blanking: 900 seconds (15 min)
- Emergency stop requires confirmation
- Print view: list, sorted by date (newest first)

### Preheat Presets

| Material | Extruder | Bed |
|---|---|---|
| PLA | 200°C | 60°C |
| PETG | 240°C | 80°C |
| ABS | 245°C | 110°C |
| ABS (eSun) | 235°C | 110°C |
| ABS (Sunlu) | 255°C | 110°C |
| ASA | 250°C | 105°C |
| TPU | 230°C | 50°C |
| Bed Only | — | 110°C |

### Custom Menus

The KlipperScreen config defines custom menu trees for:

- **Prep:** Home, QGL, G32, Bed Mesh, Clean Nozzle, Move to Centre
- **Calibrate:** Input Shaper, Pressure Advance, PID Hotend (245°C), PID Bed (110°C), Speed Test
- **Lights:** Case lights on/off, StealthBurner logo on/off
- **Fans:** Bed fans full/slow/off
- **Power:** Sleep, Heaters off, Firmware restart (with confirmations)

---

## 12. Timelapse

Moonraker-timelapse is installed as a Git repo at `/home/<USER>/moonraker-timelapse`. The Klipper macros are symlinked into the config directory:

```
~/printer_data/config/timelapse.cfg → ~/moonraker-timelapse/klipper_macro/timelapse.cfg
```

The `PRINT_END` macro calls `TIMELAPSE_TAKE_FRAME` as its final action. Timelapse is configured in `moonraker.conf` with default settings (auto-render enabled, standard frame/output paths).

---

## 13. WLED Case Lighting

An external WLED controller manages case lighting:

| Setting | Value |
|---|---|
| Address | `<WLED_IP>` |
| Protocol | HTTP |
| LED Count | 104 |
| Moonraker Section | `[wled lights]` |
| Default Preset | 1 (on startup) |

Controlled via `CASELIGHTS_ON` / `CASELIGHTS_OFF` gcode macros which call Moonraker's `set_wled_state` remote method. The `[power printer_lights]` section in Moonraker exposes this as a power device in the Fluidd UI.

---

## 14. Automated GitHub Backup

### Mechanism

The backup system uses two components:

1. **Gcode macro** (`common/github_backup.cfg`): Defines a `gcode_shell_command` named `github_backup` and a `BACKUP_CONFIG` macro.
2. **Shell script** (`github-backup.sh`): The actual Git operations.

### Backup Triggers

- **On Klipper startup:** Via delayed gcode in `common/startup.cfg` (runs 1 second after boot)
- **Nightly cron job:** Root crontab runs `github-backup.sh` at midnight (`0 0 * * *`)

### What It Does

1. `cd` to the config directory
2. Fetch from origin; rebase if remote has changes
3. If no local changes, exit cleanly
4. Stage all changes, commit with timestamp and version info (Klipper, Moonraker, Fluidd versions)
5. Push to GitHub

### Git Configuration

```
Remote: https://github.com/<GITHUB_USER>/Klipper-config.git
Branch: master
Auth: Git credential store (~/.git-credentials)
User: <YOUR_NAME> <<YOUR_EMAIL>>
```

The `.gitignore` excludes `*.bkp` files (Moonraker config backups).

---

## 15. Known Gotchas & Workarounds

### ⚠️ TRSYNC_TIMEOUT — CAN Bus Timing Fix

**File:** `/home/<USER>/klipper/klippy/mcu.py` line 256

The default `TRSYNC_TIMEOUT` is `0.025` seconds. This system has it modified to **`0.050`** seconds to resolve CAN bus timing errors that cause "Communication timeout during homing" crashes.

```python
# Line 256 of /home/<USER>/klipper/klippy/mcu.py
TRSYNC_TIMEOUT = 0.05   # Default is 0.025
```

> **⚠️ This is a source code modification.** It will be **overwritten** every time Klipper is updated via `git pull` or Moonraker's update manager. You MUST re-apply this change after every Klipper update. This is a well-known community workaround that has not been merged upstream.

### ⚠️ Octopus 12 MHz Crystal

The BTT Octopus mainboard uses a 12 MHz crystal oscillator. Klipper's default STM32F446 configuration assumes 8 MHz. If you select the wrong crystal frequency when building firmware, the MCU will fail to communicate. Always select **12 MHz** in `make menuconfig`.

### ⚠️ gcode_shell_command Extension

This is NOT part of stock Klipper. After a fresh Klipper install, you must copy it into place:

```bash
cp ~/kiauh/kiauh/extensions/gcode_shell_cmd/assets/gcode_shell_command.py ~/klipper/klippy/extras/
sudo systemctl restart klipper
```

Without this, the GitHub backup macro, camera control macros, and any other shell commands will fail to load.

### ⚠️ Filament Sensor Disabled on Startup

The filament sensor is deliberately disabled on boot (via `filament_sensor.cfg`) and only enabled inside `PRINT_START`. This prevents false runout detection during manual filament loading/unloading. If you add a new print start macro, remember to include `SET_FILAMENT_SENSOR SENSOR=filament_sensor ENABLE=1`.

### ⚠️ Probe Temperature Gating

The Tap probe's `activate_gcode` forces the extruder to 150°C before probing. If your extruder target is above 150°C, it will cool down first. This is by design — probing with a hot nozzle causes filament ooze that ruins Z accuracy. This adds time to the homing/QGL/mesh sequence.

### ⚠️ Bed Power Limited to 60%

`max_power: 0.6` on the heater bed. This is intentional for the 350mm bed to prevent overshooting and to protect the AC heater pad/SSR.

### ⚠️ Klipper `.config` Contains Last-Built MCU

The file `~/klipper/.config` only stores the last firmware configuration built. Currently it holds the EBB36 config. When building Octopus firmware, you must run `make menuconfig` fresh. Consider backing up each MCU's config:

```bash
cp ~/klipper/.config ~/klipper/.config.ebb36
cp ~/klipper/.config ~/klipper/.config.octopus
```

---

## 16. Disaster Recovery Steps

### Scenario: Complete SD Card Failure / New Pi

#### Phase 1: Base OS

1. Flash **Raspberry Pi OS Lite (Bullseye, 64-bit)** to a new SD card
2. Enable SSH, configure WiFi (`<YOUR_SSID>`, WPA2, country=GB) via `rpi-imager` or `wpa_supplicant.conf` on boot partition
3. Boot, SSH in, set hostname to `voron`:
   ```bash
   sudo raspi-config  # Set hostname, locale, timezone (Europe/London)
   ```
4. Update system:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

#### Phase 2: Boot Configuration

Edit `/boot/config.txt` and add/ensure:
```ini
dtparam=spi=on
enable_uart=1
dtoverlay=disable-bt
dtparam=i2c_arm=on
gpu_mem=256
```
Reboot.

#### Phase 3: CAN Bus Interface

Create `/etc/network/interfaces.d/can0`:
```
allow-hotplug can0
iface can0 can static
	bitrate 1000000
	up ifconfig $IFACE txqueuelen 1024
```

#### Phase 4: Install Klipper Ecosystem via KIAUH

```bash
cd ~
git clone https://github.com/dw-0/kiauh.git
cd kiauh
./kiauh.sh
```

Install (in order):
1. Klipper
2. Moonraker
3. Fluidd (on port 80)
4. KlipperScreen
5. Crowsnest

#### Phase 5: Restore Configuration

```bash
cd ~/printer_data/config
git init
git remote add origin https://github.com/<GITHUB_USER>/Klipper-config.git
git fetch origin
git checkout -f master
```

Set up Git credentials:
```bash
git config --global user.name "<YOUR_NAME>"
git config --global user.email "<YOUR_EMAIL>"
git config --global credential.helper store
# Then do a git push to trigger credential prompt
```

#### Phase 6: Install Extensions

```bash
# gcode_shell_command
cp ~/kiauh/kiauh/extensions/gcode_shell_cmd/assets/gcode_shell_command.py ~/klipper/klippy/extras/

# Moonraker-timelapse
cd ~
git clone https://github.com/mainsail-crew/moonraker-timelapse.git
# The symlink in config/ should already point to the right place
```

#### Phase 7: Apply TRSYNC_TIMEOUT Fix

```bash
# Edit ~/klipper/klippy/mcu.py
# Change line ~256 from:
#   TRSYNC_TIMEOUT = 0.025
# To:
#   TRSYNC_TIMEOUT = 0.05
sed -i 's/TRSYNC_TIMEOUT = 0.025/TRSYNC_TIMEOUT = 0.05/' ~/klipper/klippy/mcu.py
```

#### Phase 8: Build & Flash MCU Firmware

**Octopus:**
```bash
cd ~/klipper
make menuconfig
# STM32 → STM32F446 → 32KiB bootloader → 12MHz crystal → USB
make clean && make
# Flash via SD card or USB DFU
```

**EBB36:**
```bash
cd ~/klipper
make menuconfig
# STM32 → STM32G0B1 → 8KiB bootloader → 8MHz crystal → CAN PB0/PB1 → 1000000
make clean && make
python3 ~/katapult/scripts/flashtool.py -i can0 -u 2fd24cc0e083 -f ~/klipper/out/klipper.bin
```

> If the EBB36 Katapult bootloader is corrupted, you'll need to flash it via DFU (USB) first, then flash Klipper over CAN.

#### Phase 9: Install Katapult (if needed)

```bash
cd ~
git clone https://github.com/Arksine/katapult.git
cd katapult
make menuconfig
# STM32 → STM32G0B1 → 8MHz → CAN PB0/PB1 → 1000000
make clean && make
```

#### Phase 10: Set Up Cron Job

```bash
sudo crontab -e
# Add:
0 0 * * * sh ~/printer_data/config/github-backup.sh
```

#### Phase 11: Node.js (if needed)

```bash
# Node.js was installed (v20.18.1) — likely for Claude MCP or other tools
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
sudo apt install -y nodejs
mkdir ~/.npm-global
npm config set prefix '~/.npm-global'
echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc
```

#### Phase 12: Verify

1. `sudo systemctl restart klipper moonraker nginx crowsnest KlipperScreen`
2. Open Fluidd at `http://voron.local` or `http://<PRINTER_IP>`
3. Check MCU connectivity in Fluidd
4. Home printer, run QGL, verify probe works
5. Verify webcam stream
6. Run `BACKUP_CONFIG` to confirm GitHub push

---

## Appendix: USB Device Map

| Bus | Device | ID | Description |
|---|---|---|---|
| 001:014 | `1d50:614e` | Octopus (Klipper, STM32F446) |
| 001:004 | `046d:08e5` | Logitech C920 Pro HD Webcam |
| 001:003 | `1d50:606f` | Geschwister Schneider CAN adapter (gs_usb) |
| 001:002 | `2109:3431` | VIA Labs USB 3.0 Hub |

## Appendix: CAN Bus UUIDs

| MCU | UUID |
|---|---|
| Octopus (commented out in config) | `102ae6efb1e0` |
| EBB36 | `2fd24cc0e083` |

## Appendix: Directory Layout

```
/home/<USER>/
├── klipper/           # Klipper source + firmware build
├── klippy-env/        # Klipper Python venv
├── moonraker/         # Moonraker source
├── moonraker-env/     # Moonraker Python venv
├── moonraker-timelapse/  # Timelapse plugin
├── fluidd/            # Fluidd web UI (static files)
├── KlipperScreen/     # KlipperScreen source
├── .KlipperScreen-env/  # KlipperScreen Python venv
├── crowsnest/         # Crowsnest webcam streamer
├── katapult/          # Katapult CAN bootloader (formerly CanBoot)
├── CanBoot.old/       # Legacy CanBoot (pre-rename)
├── kiauh/             # KIAUH installer
├── kiauh.old/         # Previous KIAUH version
├── sonar/             # Sonar WiFi keepalive
├── backups/           # KIAUH backup directory
├── printer_data/      # Klipper runtime data
│   ├── config/        # ← THIS REPO (Git-tracked)
│   ├── gcodes/        # Uploaded gcode files (~2.7 GB)
│   ├── logs/          # Klippy, Moonraker, Crowsnest logs
│   ├── database/      # Moonraker SQL + LMDB databases
│   ├── comms/         # Unix sockets (klippy.sock, klippy.serial)
│   └── systemd/       # Service environment files
└── klipper_logs/      # Legacy log directory (from old config)
```
