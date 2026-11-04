# Voron 2.4 350mm — Disaster Recovery & System Documentation

> **Last audited:** 2026-04-20 (printer-audit skill pass)  
> **Hostname:** `voron` • **IP:** `<PRINTER_IP>` (WiFi/DHCP)  
> **Repository:** [<GITHUB_USER>/Klipper-config](https://github.com/<GITHUB_USER>/Klipper-config)  
> **SD card health:** degrading as of last audit (EXT4 errors + undervoltage events). If this doc is in use because the card died, that is expected. Read section 16 before anything else.

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
| **Probe** | Chaoticlabs CNC Tap V2 (magnetic flexure, nozzle probe, `probe:z_virtual_endstop`) |
| **Accelerometer** | ADXL345 on EBB36 (SPI) |
| **Webcam** | Logitech C920 Pro HD (USB, `046d:08e5`) |
| **LEDs** | StealthBurner RGBW Neopixels (3-chain) on EBB36 |
| **Case Lighting** | WLED controller at `<WLED_IP>` on ESP8266, 105 LEDs on device (Moonraker config currently declares 104, off-by-one is cosmetic) |
| **Filament Sensor** | Switch sensor on `PG12` (Octopus) |

### Stepper Motors (all TMC2209 UART)

| Axis | Octopus Port | Run Current | Microsteps | Notes |
|---|---|---|---|---|
| X (B motor, left) | MOTOR_0 (`PF13`) | 1.1A | 32 | 400 full steps/rev (0.9° LDO), stealthchop off, `interpolate: true` |
| Y (A motor, right) | MOTOR_1 (`PG0`) | 1.1A | 32 | 400 full steps/rev (0.9° LDO), stealthchop off, `interpolate: true` |
| Z0 (front left) | MOTOR_2 (`PF11`) | 1.0A | 16 | 80:16 gear ratio, 1.0A required for 350mm gantry (0.8A causes QGL drift) |
| Z1 (rear left) | MOTOR_3 (`PG4`) | 1.0A | 16 | 80:16 gear ratio |
| Z2 (rear right) | MOTOR_4 (`PF9`) | 1.0A | 16 | 80:16 gear ratio |
| Z3 (front right) | MOTOR_5 (`PC13`) | 1.0A | 16 | 80:16 gear ratio |
| Extruder | EBB36 (`PD0`) | 0.6A | 16 | CW2 50:10 gear ratio, `rotation_distance: 22.6789511` |

### Fan Configuration

| Fan | Pin | Type | Notes |
|---|---|---|---|
| Part Cooling (FAN0) | `ebbcan:PA0` | `[fan]` | off_below: 0.10; ABS prints capped at 30% via slicer |
| Hotend (FAN1) | `ebbcan:PA1` | `[heater_fan]` | Activates at 50°C extruder temp |
| Controller | `PD12` | `[controller_fan]` | 50% speed, **stepper-triggered** on X/Y/Z motion with 60s idle timeout (intentionally NOT tied to bed heater so it does not run during cold-bed idle or PLA prints) |
| Exhaust (FAN3) | `PD13` | `[fan_generic]` | **Manual** via `VENT_CHAMBER` macro (100% for 10 min then auto-stop). Intentionally NOT a heater_fan so the chamber stays hot during ABS prints. |
| Bed Fans | `PD14` | `[fan_generic]` | `BedFans` macro chain: slow while heating above 90°C, fast once at target, **suppressed entirely during active prints** to prevent ABS warping |

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
| **Klipper** | `v0.13.0-540-g57c2e0c9` (as of 2026-04-20) | `/home/<USER>/klipper` | [Klipper3d/klipper](https://github.com/Klipper3d/klipper) |
| **Moonraker** | `v0.10.0-8-g293a4cf` (as of 2026-04-20) | `/home/<USER>/moonraker` | [Arksine/moonraker](https://github.com/Arksine/moonraker) |
| **Fluidd** | `v1.36.2` (as of 2026-04-20) | `/home/<USER>/fluidd` | [fluidd-core/fluidd](https://github.com/fluidd-core/fluidd) |
| **KlipperScreen** | `v0.4.6-41-g5a5ae382` (as of 2026-04-20) | `/home/<USER>/KlipperScreen` | [KlipperScreen/KlipperScreen](https://github.com/KlipperScreen/KlipperScreen) |
| **Crowsnest** | `v4.1.17-1-g9cc3d4a` (as of 2026-04-20) | `/home/<USER>/crowsnest` | [mainsail-crew/crowsnest](https://github.com/mainsail-crew/crowsnest) |
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
    ├── wled_lights.cfg      # WLED preset switching, auto-transitions, test macros
    └── scripts/
        └── c920_disable_autofocus.sh  # v4l2-ctl autofocus disable script
```

### Motion System Settings

```
Kinematics: CoreXY
Max velocity: 500 mm/s
Max acceleration: 10,000 mm/s²       (headroom only; input_shaper caps effective accel ~4,100 mm/s²)
Max Z velocity: 30 mm/s
Max Z acceleration: 350 mm/s²
Square corner velocity: 8.0 mm/s     (raised from stock 5.0 for faster corners)
Minimum cruise ratio: 0.5            (replaces deprecated max_accel_to_decel)
```

### Input Shaper

Current values (in `printer.cfg` SAVE_CONFIG block, body commented out):

```
X axis: mzv @ 54.4 Hz
Y axis: mzv @ 38.4 Hz
```

Shaper calibration graphs are stored at `voron/shaper_calibrate_x.png` and `voron/shaper_calibrate_y.png`. Effective acceleration ceiling is Y-limited at approximately 4,100 mm/s². Re-run `SHAPER_CALIBRATE` after any toolhead mass change (new hotend, extruder swap, probe change).

### Probe (Chaoticlabs CNC Tap V2)

- Replaces the Voron Tap that was on this printer previously. Magnetic flexure, nozzle-contact. BTT Eddy Duo was trialled and abandoned before this.
- Pin `^!ebbcan:PB9` (pullup + invert for the open-drain output)
- Uses nozzle as probe (no X/Y offset)
- Z offset: **-0.458** (in SAVE_CONFIG section; normal range for this probe is -0.3 to -0.6)
- 5 samples, median result, 0.0125 tolerance, 5 retries (tightened from Voron defaults)
- Probe speed 5 mm/s, sample retract 3.0 mm
- **Activate gcode** forces extruder below 150°C before probing (prevents filament ooze affecting readings)
- Higher negative z_offset = nozzle closer to bed

> **⚠️ Do NOT use `Z_OFFSET_APPLY_PROBE` with this probe.** Klipper's built-in version applies the wrong sign when the nozzle is the probe (true for Voron Tap, CNC Tap, and similar designs). Use the custom `SAVE_Z_OFFSET` macro in `common/save_z_offset.cfg` instead. See `Z_OFFSET_TAP_BUG.md` in this repo for the full explanation.

**Z calibration workflow:** `PROBE_CALIBRATE` for a rough starting offset at full print temperature, then live first-layer test with baby-stepping, then `SAVE_Z_OFFSET` then `SAVE_CONFIG`. Never calibrate cold (thermal expansion is approximately 0.09 to 0.12 mm for ABS print temps).

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
Tolerance: 0.0250 mm    (realistic floor is ~0.02 mm for belt-driven Z; tighter values thrash)
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

1. Stop print monitor, disable filament sensor
2. Retract 3mm
3. Compute safe X/Y/Z move directions based on current position
4. Lift Z, move X/Y to remove stringing
5. Turn off heaters, turn off part fan
6. Take timelapse frame (`TIMELAPSE_TAKE_FRAME`) BEFORE parking so the final frame shows the finished print
7. Park at rear centre (`X175 Y350`)
8. Clear bed mesh (`BED_MESH_CLEAR`)
9. Leave steppers energised -- idle_timeout (30 min) handles disable as a safety net. Keeping steppers energised preserves homing and QGL state for back-to-back prints.
10. LED to Complete preset (green breathing), auto-return to Idle after 15 min then Off after 30 more

### PID Values (Auto-tuned, in SAVE_CONFIG)

```
Extruder: Kp=30.557, Ki=1.959, Kd=119.173
Bed:      Kp=38.678, Ki=1.417, Kd=263.975
```

### Bed Fan Control

The `bedfans.cfg` macro overrides `M140`, `M190`, `SET_HEATER_TEMPERATURE`, and `TURN_OFF_HEATERS` to automatically manage bed fans:

- **Threshold:** 90°C bed target
- **Below threshold:** Fans off
- **Heating above threshold:** Slow speed (0.4)
- **At temperature:** Fast speed (1.0)
- Monitoring loop checks every 5 seconds until target reached
- **Suppressed entirely during active prints** (`printer.print_stats.state == "printing"`) to prevent ABS warping. The override chain plus the `bedfanloop` delayed gcode both check print state. `PRINT_START` also issues `UPDATE_DELAYED_GCODE ID=bedfanloop DURATION=0` and `BedFansOff` before entering the printing phase as a belt-and-braces.

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

Moonraker manages updates for: KlipperScreen, Fluidd, Crowsnest, Timelapse, and the Klipper/Moonraker repos themselves.

**Channel configuration (post-audit):**
- Global `[update_manager] channel: stable` -- applies to Klipper and Moonraker
- `[update_manager KlipperScreen] channel: dev` -- explicitly pinned
- `[update_manager crowsnest] channel: dev` -- explicitly pinned
- `[update_manager timelapse] channel: dev` -- explicitly pinned
- Fluidd is `type: web` which is inherently stable-channel (follows GitHub releases)
- klipper_estimator is `type: executable` and Moonraker-managed natively

**Refresh interval:** 168 hours (7 days).

If you ever see Moonraker flagging dozens of commits behind for Klipper or Moonraker despite frequent updates, check that the global channel hasn't been reverted to `dev`.

### Webcam Configuration

Two webcams defined in `moonraker.conf`:

**`[webcam Top]`** -- Logitech C920 Pro HD, primary print view:
- Service: `camera-streamer-adaptive`
- Target FPS: 15
- Stream URL: `/webcam/webrtc` (WebRTC, low latency)
- Snapshot URL: `/webcam/snapshot`
- Aspect ratio: 16:9

**`[webcam Rear]`** -- Arducam IMX179 8MP, wider-angle view used for timelapse:
- Service: `mjpegstreamer-adaptive`
- Target FPS: 15
- Stream URL: `/webcam2/?action=stream`
- Snapshot URL: `/webcam2/?action=snapshot`
- Aspect ratio: 16:9

The URL differences matter: the Top (camera-streamer) uses `/webcam/snapshot` not `/webcam/?action=snapshot`. Using the wrong URL pattern returns HTTP 500. If after a rebuild the Top snapshot endpoint breaks, it's this.

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

Two cameras sharing USB 2.0 bus (both enumerate on Bus 01 regardless of which physical Pi port they're plugged into). The resolution/FPS values below are the result of bandwidth tuning: 1080p @ 30fps on the C920 starves the Arducam because the C920 at Alt=10 reserves most of the isochronous bandwidth. The 720p @ 15fps settings below are the stable combination.

**`[cam 1]` -- Logitech C920 Pro (Top):**

| Setting | Value |
|---|---|
| Mode | `camera-streamer` (WebRTC + MJPEG) |
| RTSP | Enabled on port 8554 |
| HTTP Port | 8080 (served to `/webcam/` via nginx) |
| Device | `/dev/v4l/by-id/usb-046d_HD_Pro_Webcam_C920-video-index0` |
| Resolution | **1280×720** (reduced from 1080p for bus bandwidth) |
| Max FPS | **15** |

**`[cam 2]` -- Arducam IMX179 8MP (Rear):**

| Setting | Value |
|---|---|
| Mode | `ustreamer` (camera-streamer stalls this camera: periodic GET_DEF on unsupported UVC control 12 blocks the capture pipeline) |
| RTSP | Not supported in ustreamer |
| HTTP Port | 8081 (served to `/webcam2/` via nginx) |
| Device | `/dev/v4l/by-id/usb-Arducam_Arducam_IMX179_8MP_Camera_YLAF20221208V0-video-index0` |
| Resolution | 1280×720 |
| Max FPS | 15 |
| Encoder | `CPU` (`custom_flags: --encoder=CPU`) to prevent hardware codec contention with camera-streamer on /dev/video10+11 |

**Log level:** `quiet` (was `verbose` during initial bring-up; dropped to quiet on 2026-04-20 to cut daily log churn of 2.5 MB per file).

### Camera Script

A C920 autofocus disable script exists at `scripts/c920_disable_autofocus.sh`. It uses `v4l2-ctl` to set `focus_auto=0` and `focus_absolute=30`. **Not currently hooked into any startup trigger** -- if autofocus behaviour matters (for timelapse especially), run this script manually after Crowsnest restarts. The corresponding gcode macros in `voron/c920.cfg` are just comments pointing to this script.

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
| Cooldown | 0°C | 0°C |

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

An external WLED controller manages case lighting with 8 presets tied to printer states:

| Setting | Value |
|---|---|
| Address | `<WLED_IP>` |
| Protocol | HTTP |
| LED Count | 105 on device (Moonraker declares 104; the last LED is unaddressable by macros) |
| Firmware | WLED 0.15.3 for ESP8266 (AC108 build) |
| Moonraker Section | `[wled lights]` |

### Preset Map

| Preset | State | Effect |
|--------|-------|--------|
| 1 | Idle / Standby | Solid warm white 30% |
| 2 | Heating | Breathe deep orange |
| 3 | Printing | Solid neutral white 85% |
| 4 | Homing / QGL / Meshing | Scan blue |
| 5 | Cleaning nozzle | Chase cyan |
| 6 | Print complete | Breathe green |
| 7 | Error / Cancelled | Breathe red |
| 8 | Paused | Blink amber |
| 9 | Filament change | Chase purple |

Local backup of preset JSON is in `wled_presets.json`. If the WLED device is ever wiped, import that file via the WLED web UI to restore the preset set.

### Auto-transitions

- **Print complete**: Green (preset 6) for 15 min → idle warm white (preset 1) for 30 min → off
- **Cancelled**: Red (preset 7) for 15 min → idle → off (same timer chain)
- Any new state change cancels pending timers

### Integration

Presets are called from the `STATUS_*` macros in `stealthburner_leds.cfg` via `_SET_CASE_LEDS PRESET=N` (defined in `wled_lights.cfg`). The `PRINT_END`, `CANCEL_PRINT`, `PAUSE`, and `RESUME` macros also set appropriate presets directly.

Manual control via `CASELIGHTS_ON` / `CASELIGHTS_OFF` macros and KlipperScreen menu is preserved. The `[power printer_lights]` section in Moonraker exposes this as a power device in the Fluidd UI.

Test macros (`TEST_WLED_IDLE`, `TEST_WLED_HEATING`, etc.) are available in Fluidd for previewing each preset.

---

## 14. Automated GitHub Backup

### Mechanism

The backup system uses two components:

1. **Gcode macro** (`common/github_backup.cfg`): Defines a `gcode_shell_command` named `github_backup` and a `BACKUP_CONFIG` macro.
2. **Shell script** (`scripts/github-backup.sh`): The actual Git operations.

### Backup Triggers

- **On Klipper startup:** Via delayed gcode in `common/startup.cfg` (`initial_duration: 30` -- waits 30 seconds so Moonraker webhooks register first)
- **Nightly cron job:** **lee's** crontab (not root) runs `/bin/bash /home/lee/printer_data/config/scripts/github-backup.sh` at midnight. Must be lee's crontab, not root's -- see "Credential file ownership" gotcha below. Absolute paths only, no `~`.
- **Manual:** `BACKUP_CONFIG` macro in Fluidd calls the same shell command.

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

**Credential file ownership (load-bearing detail):**

The file `/home/lee/.git-credentials` MUST be owned by `lee:lee` with mode `0600`. If root ever does a `git push` in lee's repo (easy to happen via SSH as root over MCP or an errant `sudo`), the credential helper writes the file as root-owned, and every subsequent `git push` by the cron script fails with:

```
fatal: could not read Username for 'https://github.com': No such device or address
```

Failures are silent: the cron doesn't mail (mail isn't set up on the printer), and the script used to swallow the error. Rewritten script now exits non-zero and writes status to `/tmp/github-backup-status`.

**If this ever happens, the fix is one line:**

```bash
sudo chown lee:lee /home/lee/.git-credentials && sudo chmod 600 /home/lee/.git-credentials
```

**The `.gitignore` excludes:**
- `*.bak`, `*.bkp`, `*.backup.*` (backup clutter)
- `*.orig`, `*.tmp`, `*.swp` (editor scratch)
- `printer-*_*.cfg` (Fluidd's timestamped config snapshots)
- `__pycache__/`, `*.pyc`, `.DS_Store`

---

## 15. Known Gotchas & Workarounds

### ⚠️ Git credential file ownership (recurring pain point)

The single most-likely reason for "GitHub backup not working" is that `/home/lee/.git-credentials` has ended up owned by root (mode 0600 root:root) instead of lee:lee. Lee's user then cannot read its own credentials file, `git push` fails with "could not read Username for https://github.com", and the script fails every night in silence.

**Symptoms:**
- `/tmp/github-backup-status` shows `FAIL: git push failed; check /home/lee/.git-credentials ownership`
- `cd /home/lee/printer_data/config && sudo -u lee git push --dry-run` shows the "could not read Username" error
- Commits pile up locally but never hit GitHub

**How it happens:**
- Root runs `git push` on behalf of lee (for example via an SSH MCP session)
- The credential helper (`credential.helper = store`) writes the file at whatever UID is running
- Lee's future pushes fail because lee can't read root-owned files

**Fix:**
```bash
sudo chown lee:lee /home/lee/.git-credentials
sudo chmod 600 /home/lee/.git-credentials
```

**Prevention:** the backup script now explicitly `export HOME=/home/lee` so it always uses lee's credential path, regardless of which user invokes it. Don't run `git push` as root in lee's repos. If you absolutely must, `sudo -u lee git push` instead.

### ⚠️ TRSYNC_TIMEOUT — CAN Bus Timing Fix

**File:** `/home/<USER>/klipper/klippy/mcu.py` line 256

The default `TRSYNC_TIMEOUT` is `0.025` seconds. This system has it modified to **`0.050`** seconds to resolve CAN bus timing errors that cause "Communication timeout during homing" crashes.

```python
# Line 256 of /home/<USER>/klipper/klippy/mcu.py
TRSYNC_TIMEOUT = 0.05   # Default is 0.025
```

> **⚠️ This is a source code modification.** It will be **overwritten** every time Klipper is updated via `git pull` or Moonraker's update manager. This is a well-known community workaround that has not been merged upstream.

**Automated fix:** A systemd drop-in ensures this patch is re-applied automatically on every Klipper start (including after updates):

```
/etc/systemd/system/klipper.service.d/fix-trsync.conf
```

```ini
[Service]
ExecStartPre=/bin/sed -i 's/TRSYNC_TIMEOUT = 0.025/TRSYNC_TIMEOUT = 0.05/' /home/<USER>/klipper/klippy/mcu.py
```

After a fresh OS install, recreate this drop-in (see Phase 7 below), then run `sudo systemctl daemon-reload`.

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

Set up Git credentials (run as **lee**, never as root):

> **Watertight rule:** Everything in this phase runs as `lee`. If you are SSH'd in as `root` or using `sudo`, stop and `su - lee` first. The very first `git push` writes `~/.git-credentials` at whatever UID is running. If that ends up `root:root`, the nightly cron backup will fail silently forever until you chown it back. This has burned us before (March 2026). See section 15 "Git credential file ownership" for the recovery one-liner.

```bash
# Confirm you are lee before proceeding
whoami   # must print: lee

git config --global user.name "<YOUR_NAME>"
git config --global user.email "<YOUR_EMAIL>"
git config --global credential.helper store

# Trigger the credential prompt with a push. Enter your GitHub username and
# a Personal Access Token (classic, repo scope) when prompted -- not a password.
git push

# Verify the credentials file ownership. MUST be lee:lee, mode 0600.
ls -la ~/.git-credentials
# Expected: -rw------- 1 lee lee ... /home/lee/.git-credentials
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

Apply the one-time fix and create the systemd drop-in so it survives all future Klipper updates automatically:

```bash
# Apply the fix now
sed -i 's/TRSYNC_TIMEOUT = 0.025/TRSYNC_TIMEOUT = 0.05/' ~/klipper/klippy/mcu.py

# Create systemd drop-in to auto-patch on every Klipper start
sudo mkdir -p /etc/systemd/system/klipper.service.d
sudo tee /etc/systemd/system/klipper.service.d/fix-trsync.conf << 'EOF'
[Service]
# CAN bus fix: patch TRSYNC_TIMEOUT from 0.025 to 0.05 before Klipper starts.
# Required for reliable CAN communication with EBB36.
# This survives Klipper updates which overwrite mcu.py.
ExecStartPre=/bin/sed -i 's/TRSYNC_TIMEOUT = 0.025/TRSYNC_TIMEOUT = 0.05/' /home/<USER>/klipper/klippy/mcu.py
EOF
sudo systemctl daemon-reload
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

**Important:** cron must run as **lee**, not root. Do NOT use `sudo crontab -e`.

```bash
crontab -e    # as lee
# Add:
# Daily config backup to GitHub at 00:00 (runs as lee so credentials work)
0 0 * * * /bin/bash /home/lee/printer_data/config/scripts/github-backup.sh
```

Verify credentials are accessible:

```bash
ls -la ~/.git-credentials
# Must show: -rw------- 1 lee lee ... /home/lee/.git-credentials
# If it shows root:root, chown it back:
#   sudo chown lee:lee ~/.git-credentials && sudo chmod 600 ~/.git-credentials
```

After the first cron firing, confirm:

```bash
cat /tmp/github-backup-status
# Expected: YYYY-MM-DD HH:MM:SS [OK] <action>, pushed N commit(s)
# OR:      YYYY-MM-DD HH:MM:SS [OK] clean, nothing to push
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
│   │   ├── printer.cfg                # Main Klipper config
│   │   ├── moonraker.conf             # Moonraker config
│   │   ├── crowsnest.conf             # Webcam config
│   │   ├── KlipperScreen.conf         # Touchscreen UI
│   │   ├── saved_variables.cfg        # PA calibration + print_monitor state
│   │   ├── wled_presets.json          # WLED preset backup
│   │   ├── timelapse.cfg              # Symlink to moonraker-timelapse
│   │   ├── Z_OFFSET_TAP_BUG.md        # Tap sign-bug workaround docs
│   │   ├── common/                    # Reusable macros
│   │   │   ├── save_z_offset.cfg      # Tap-safe Z offset save
│   │   │   ├── virtual_tools.cfg      # T0-T9 for multi-colour on one extruder
│   │   │   └── (see tree above)
│   │   ├── voron/                     # Build-specific macros
│   │   │   ├── print_monitor.cfg      # Claude Code print monitor integration
│   │   │   └── (see tree above)
│   │   └── scripts/
│   │       ├── github-backup.sh       # Auto-backup (runs as lee)
│   │       ├── c920_disable_autofocus.sh
│   │       └── fix_trsync.sh          # One-shot TRSYNC patcher
│   ├── gcodes/        # Uploaded gcode files (~3 GB; prune after print if disk pressure)
│   ├── logs/          # klippy.log, moonraker.log, crowsnest.log, KlipperScreen.log
│   ├── database/      # Moonraker SQL + LMDB databases
│   ├── comms/         # Unix sockets (klippy.sock, klippy.serial)
│   └── systemd/       # Service environment files
└── klipper_logs/      # Legacy log directory (from old config)
```
