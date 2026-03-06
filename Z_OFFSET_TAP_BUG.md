# Z_OFFSET_APPLY_PROBE Bug with Voron Tap

## Summary

**Do NOT use `Z_OFFSET_APPLY_PROBE` with Voron Tap.** It applies baby-step adjustments with the wrong sign, causing the z_offset to drift in the opposite direction. Use the `SAVE_Z_OFFSET` macro instead.

## The Problem

Klipper's `Z_OFFSET_APPLY_PROBE` was designed for traditional probe setups (BLTouch, inductive sensor) where the probe is a separate device offset from the nozzle, and Z homes against a physical endstop switch. Its internal formula is:

```
new_z_offset = old_z_offset - gcode_z_offset
```

With Voron Tap, the nozzle **is** the probe and Z homes via `probe:z_virtual_endstop`. This inverts the sign relationship between gcode offset and probe offset. The correct formula for Tap is:

```
new_z_offset = old_z_offset + gcode_z_offset
```

## What Happens

1. z_offset is -1.305, first layer is too far from bed
2. Baby-step -0.075mm during print (nozzle moves closer, first layer now perfect)
3. Run `Z_OFFSET_APPLY_PROBE`
4. Klipper calculates: -1.305 - (-0.075) = **-1.230** (less negative = further from bed)
5. `SAVE_CONFIG` writes -1.230
6. After restart, first layer is even worse — 0.150mm too far from where it should be

The correct result should have been: -1.305 + (-0.075) = **-1.380** (more negative = closer to bed).

## The Fix

Use `SAVE_Z_OFFSET` instead. This macro negates the gcode offset before passing it to `Z_OFFSET_APPLY_PROBE`, correcting the sign:

```
SAVE_Z_OFFSET    ; calculates and queues the correct offset
SAVE_CONFIG      ; persists to printer.cfg and restarts
```

The macro displays the calculation so you can verify before saving:

```
// Current probe z_offset: -1.305
// Baby-step Z adjustment: -0.075
// New probe z_offset:     -1.380
// New z_offset queued. Run SAVE_CONFIG to persist.
```

## Correct Workflow

1. Start a print with your current z_offset
2. Baby-step Z during the first layer until it looks perfect
3. Run `SAVE_Z_OFFSET` in the Fluidd/Mainsail console
4. Verify the displayed calculation makes sense
5. Run `SAVE_CONFIG` when convenient (this restarts Klipper)

## Why Not Just Use PROBE_CALIBRATE?

`PROBE_CALIBRATE` (paper test) works correctly, but it calibrates at the probing temperature (150°C). When the extruder then heats to printing temperature (e.g. 245°C for ABS), thermal expansion of the nozzle/heatbreak shifts Z by approximately 0.08-0.12mm. This means a PROBE_CALIBRATE result will always need baby-step correction for the actual printing temperature.

The baby-step-and-save workflow captures the offset at the real printing temperature, which is more accurate.

## Date Discovered

6 March 2026 — diagnosed from git history showing z_offset oscillating between sessions. Root cause confirmed by correlating klippy.log probe events with Fluidd console baby-step commands.
