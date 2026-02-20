# WLED Status Lighting Plan

> **Status:** Planned — not yet implemented  
> **Hardware:** 104 RGBW LEDs, WLED controller at `<WLED_IP>`  
> **Integration:** Moonraker WLED module → Klipper STATUS_* macros

## Overview

Use WLED presets to match case lighting to printer state. Each state gets a
dedicated preset created in WLED's web UI, then called from the existing
Klipper STATUS_* macros via `action_call_remote_method`.

## Proposed Preset Map

| Preset | State | WLED Effect | Colour | Notes |
|--------|-------|-------------|--------|-------|
| 1 | Idle / Standby | Solid | Warm white `(255, 180, 100)` ~30% | Existing preset — review brightness |
| 2 | Heating | Breathe | Deep orange `(255, 100, 0)` | Slow pulse. Alternative: Candle for flickering warmth |
| 3 | Printing | Solid | Neutral/pure white via W channel, 80-100% | Functional — clear visibility for camera/timelapse |
| 4 | Homing / Levelling / Meshing | Scan (Knight Rider) | Blue `(0, 80, 255)` | Scanning bar effect — looks clean on 104 LEDs |
| 5 | Cleaning nozzle | Chase | Cyan `(0, 255, 200)` medium speed | Brief and distinctive |
| 6 | Print complete | Breathe | Green `(0, 255, 50)` | Auto-return to idle white after 5-10 min via delayed gcode |
| 7 | Error / Halted | Breathe | Red `(255, 0, 0)` slow | Visible across the room |
| 8 | Paused / Filament change | Blink | Amber `(255, 160, 0)` ~1s cycle | Hazard-light feel. Alternative: slow Strobe |

## Implementation Steps

### 1. Create WLED presets

Open WLED web UI and create presets 1-8 with the effects and colours above.
Save each to the corresponding preset slot number.

### 2. Add case light macro

```ini
[gcode_macro _SET_CASE_LEDS]
gcode:
    {% set PRESET = params.PRESET|default(1)|int %}
    {action_call_remote_method("set_wled_state", strip="lights", state=True, preset=PRESET)}
```

### 3. Wire into existing STATUS_* macros

Add a `_SET_CASE_LEDS PRESET=N` call to each macro in `stealthburner_leds.cfg`:

```
status_ready      → _SET_CASE_LEDS PRESET=1  (idle warm white)
status_heating    → _SET_CASE_LEDS PRESET=2  (breathing orange)
status_printing   → _SET_CASE_LEDS PRESET=3  (bright white)
status_homing     → _SET_CASE_LEDS PRESET=4  (scanning blue)
status_leveling   → _SET_CASE_LEDS PRESET=4  (scanning blue)
status_meshing    → _SET_CASE_LEDS PRESET=4  (scanning blue)
status_cleaning   → _SET_CASE_LEDS PRESET=5  (chase cyan)
status_off        → set_wled_state state=False
```

### 4. Print complete with auto-return to idle

In PRINT_END, after STATUS_OFF, add:

```ini
_SET_CASE_LEDS PRESET=6                                    ; green "complete"
UPDATE_DELAYED_GCODE ID=_case_leds_idle DURATION=300       ; back to idle after 5 min

[delayed_gcode _case_leds_idle]
gcode:
    _SET_CASE_LEDS PRESET=1
```

## Design Notes

- **Breathe** is the standout effect — smooth pulse looks great on 104 LEDs in an enclosed space
- **Scan/Knight Rider** during homing is both functional and visually impressive
- **Candle** during heating is natural-looking and avoids "RGB gamer" aesthetics
- **Keep printing as solid white** — colour effects make it hard to spot quality issues and mess with timelapse colour balance
- **Avoid** Rainbow, Fire, Chase Rainbow during printing — distracting over long prints
- Existing `CASELIGHTS_ON` / `CASELIGHTS_OFF` macros and KlipperScreen menu entries continue to work independently

## Prerequisites

- Note which WLED presets are currently in use before creating new ones
- Test each preset in WLED web UI before wiring into macros
- Verify Moonraker WLED connection is stable (`[wled lights]` in moonraker.conf)
