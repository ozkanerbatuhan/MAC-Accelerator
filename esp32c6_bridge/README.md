# ESP32-C6 UART <-> WiFi/TCP Bridge (for NEORV32 on ZedBoard)

Bridges the NEORV32 PL UART0 over WiFi instead of a USB-serial cable. The ESP32-C6
forwards FPGA UART bytes to a Python server (printed in your PC terminal) and sends
PC->FPGA bytes back (so the NEORV32 bootloader is drivable over WiFi). The onboard
WS2812 RGB LED smoothly shifts hue on every byte of traffic = liveness indicator.

## Wiring (3.3V only — never feed 5V to the C6)
| ZedBoard PMOD JA | ESP32-C6 |
|---|---|
| JA1 (FPGA TX)    | GPIO4 (UART RX) |
| JA2 (FPGA RX)    | GPIO5 (UART TX) |
| GND              | GND |

Baud is fixed at **19200-8N1** to match the NEORV32 bootloader.

## Configure
Edit the top of `main/bridge_main.c`:
- `WIFI_SSID` / `WIFI_PASS` — already set to `Batu50` / `123456789`.
- `SERVER_IP` — **set to your PC's LAN IP** (where `server.py` runs). Find it with
  `ipconfig` (Windows) / `ip addr` (Linux). `SERVER_PORT` default 5005.

## Build & flash (ESP-IDF v5.1+)
```
cd esp32c6_bridge
idf.py set-target esp32c6
idf.py build
idf.py -p <COMx> flash monitor      # monitor only shows wifi/connect logs, not bridged data
```
The `espressif/led_strip` component is pulled automatically (idf_component.yml).

## Run the server (PC)
```
cd esp32c6_bridge/server
python server.py --port 5005
```
Then power the board / press BTNC reset → the NEORV32 bootloader banner appears in
the server terminal. The RGB LED hue should shift as bytes flow.

### Uploading a program over the bridge
At the server prompt:
```
/raw u                                  # tell the bootloader to expect an upload
/sendfile D:/vivado projects/MAC-Accelerator/sw/mac_demo/neorv32_exe.bin
/raw e                                  # execute
```
(Exact bootloader key sequence per the NEORV32 docs; `u`=upload, `e`=execute.)

## Notes
- LED is on GPIO8 (ESP32-C6-DevKitC default WS2812). Change `LED_GPIO` if your board differs.
- If GPIO4/5 are taken on your board, change `UART_RX_PIN`/`UART_TX_PIN` (C6 GPIO matrix is flexible; avoid strapping pins 8/9/15).
- No serial output of bridged data by design — it travels over WiFi to `server.py`.
