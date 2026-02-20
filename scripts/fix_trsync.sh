#!/bin/bash
sed -i 's/TRSYNC_TIMEOUT = 0.025/TRSYNC_TIMEOUT = 0.05/g' ~/klipper/klippy/mcu.py
echo "TRSYNC_TIMEOUT patched to 0.05"
sudo systemctl restart klipper