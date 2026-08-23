# Tower Hardware

This document records the physical hardware required by the current Tower
installation, what is installed now, and the known connections used by Tower
v0.11.01.

`Installed` means the component is part of the present build. A software check
can confirm an I2C address, GPIO interface, or network endpoint, but it cannot
always prove that the physical component itself is electrically connected and
working.

## Main computers and controllers

| Status | Component | Connection | Purpose |
|---|---|---|---|
| Installed | Raspberry Pi 3 Model A+ | Wi-Fi; local GPIO and I2C bus 1 | Runs Tower and the `rf-tower.service` systemd service |
| Installed | Raspberry Pi Pico 2 W (`tower-pico`) | Wi-Fi, `192.168.2.30:42101` | Generates IR carriers and controls the six IR transmitter outputs |

The Pico and its IR transmitter board use a separate regulated 5 V supply.
Connect +5 V to Pico `VSYS` (physical pin 39), connect the supply ground to a
Pico ground, and share that ground with the transmitter circuit. Do not connect
the external adapter's +5 V rail to the Raspberry Pi 5 V rail.

## Local I2C hardware

All installed local I2C devices use `/dev/i2c-1`.

| Status | Component | Address | Purpose |
|---|---|---:|---|
| Installed | ADS1115 4-channel ADC | `0x48` | Analogue measurements; RF receiver RSSI currently uses AIN0 |
| Installed | BME688 environmental sensor | `0x76` | Room temperature, humidity, pressure, and gas resistance |
| Installed | HD44780-compatible 20x4 LCD with I2C backpack | `0x27` | Startup diagnostics and normal Tower status display |

## IR receiver array

The six demodulating receivers are connected directly to Raspberry Pi GPIOs.
Tower discovers their live `/dev/lircX` devices by GPIO rather than relying on
unstable Linux `rcX` numbering.

| Status | Receiver | Carrier | BCM GPIO | Position |
|---|---|---:|---:|---|
| Installed | TSOP38230 | 30 kHz | 17 | West |
| Installed | TSOP38233 | 33 kHz | 18 | West |
| Installed | TSOP34836 | 36 kHz | 27 | West |
| Installed | TSOP38238 | 38 kHz | 22 | South |
| Installed | TSOP38240 | 40 kHz | 23 | South |
| Installed | TSOP38256 | 56 kHz | 25 | South |

During service startup, the LCD displays:

```text
Tower v0.11.01 BOOT
30 33 36 38 40 56
OK OK OK OK OK OK
>> Init.     IR-Rec.
```

The third row is filled from left to right. `OK` means Tower resolved the
expected GPIO-backed LIRC device. `--` means that device was not found. This is
a kernel-interface check, not an electrical or optical test of the receiver.
The normal Tower boot header remains visible and `IR-Rec.` identifies the
hardware being initialized on the standard boot progress row.

## IR transmitters

All six transmitter definitions are active and routed through Tower Pico
outputs 1 through 6, which map directly to GP1 through GP6.

| Status | Tower ID | Pico output / GPIO | Driver transistor | IR emitter |
|---|---|---|---|---|
| Installed / active | `Tower-IR-TX-001` | 1 / GP1 | BC817-40 | Vishay TSAL6200 |
| Installed / active | `Tower-IR-TX-002` | 2 / GP2 | BC817-40 | Clear 5 mm IR LED, generic/unknown |
| Installed / active | `Tower-IR-TX-003` | 3 / GP3 | BC817-40 | Clear 10 mm IR LED, generic/unknown |
| Installed / active | `Tower-IR-TX-004` | 4 / GP4 | BC817-40 | Vishay TSAL6100 |
| Installed / active | `Tower-IR-TX-005` | 5 / GP5 | BC817-40 | Vishay TSAL4400 |
| Installed / active | `Tower-IR-TX-006` | 6 / GP6 | FMMT491A | Vishay TSAL6200 |

Each IR LED is driven through its listed transistor and the existing
current-limiting circuitry; no IR emitter is powered directly from a Pico GPIO.
This mixed-emitter array is intentionally useful for comparing optical range,
beam pattern, and protocol performance between generic emitters and known
Vishay TSAL parts. The complete Pico and power setup is in
[`Pico-Remote-Controller.md`](Pico-Remote-Controller.md).

Current field observations are deliberately treated as device-specific rather
than universal transmitter ratings:

- `Tower-IR-TX-001` (BC817-40 + TSAL6200) has shown the strongest practical
  Denon AVR-X2800H room coverage.
- `Tower-IR-TX-004` (BC817-40 + TSAL6100) works reliably with the Denon but is
  more dependent on room reflection geometry.
- `Tower-IR-TX-005` (BC817-40 + TSAL4400) is reliable with the Denon at a
  50% per-transmitter duty override; the Denon device default remains 40%.
- `Tower-IR-TX-006` (FMMT491A + TSAL6200) can transmit the KPN Media Box signal
  successfully but has performed poorly with the Denon 38 kHz signal. This
  confirms that transmitter compatibility depends on the device/protocol and
  driver/emitter combination.
- The generic clear emitters on TX-002 and TX-003 have substantially shorter
  useful range in current testing and are candidates for later replacement
  with additional TSAL6100/TSAL6200 emitters.

Room geometry is part of real-world IR performance. During testing, moving a
projection sheet removed a useful wall-reflection path and made several Denon
outputs appear to have failed even though their electrical/software behavior
was unchanged. Direct-line and room-bounce performance should therefore not be
treated as the same measurement.

The Pico firmware currently permits carrier duty up to 80%. The normal
calibration range is capped at 60%; 70/80% are experimental fallback settings
and are only attempted after explicit operator approval on the best responding
transmitter. The actual peak LED current has not yet been instrumented, so
70/80% must not be documented as guaranteed continuous electrical ratings.

## RF hardware

| Status | Component | Connection | Purpose |
|---|---|---|---|
| Installed / working | FS1000A 433 MHz transmitter | BCM GPIO24 | Sends commands to the paired 433 MHz power devices |
| Installed / reception still under development | Aurel RX-4MM5-F 433 MHz receiver | DATA on provisional BCM GPIO4; RSSI on ADS1115 AIN0 | RF capture and diagnostics |

The Aurel DATA and RSSI assignments are still provisional in v0.11.01. Its
final ENABLE connection is not yet documented, so these values must not be
treated as the finished RF receiver wiring specification.

## Local control

| Status | Component | Connection | Purpose |
|---|---|---|---|
| Installed | Momentary push button | Between BCM GPIO26 and ground; internal pull-up | Controls the LCD backlight |

Button behavior:

- Single press: turn the backlight on for 30 seconds.
- Double press: lock the backlight on.
- Another double press: turn the backlight off.
- Single press while locked on: return to timed operation.

## Remote aquarium sensor

This hardware is not mounted in the main Tower, but the current Tower service
depends on it for aquarium temperature readings.

| Status | Component | Connection | Purpose |
|---|---|---|---|
| Installed / remote | Raspberry Pi temperature node | Wi-Fi, `192.168.2.26:8765` | Serves the `/temperature` HTTP endpoint |
| Installed / remote | Waterproof DS18B20 | Sensor ID `28-000008c84830`; connected to the remote Pi | Aquarium water temperature |

Tower polls this source every 30 seconds and stores up to 504 hourly readings,
representing three weeks of history.

## Current connection summary

| Interface | Assignment |
|---|---|
| I2C bus 1 | LCD `0x27`, ADS1115 `0x48`, BME688 `0x76` |
| BCM GPIO4 | Aurel RF DATA, provisional |
| BCM GPIO17, 18, 27, 22, 23, 25 | Six IR receiver outputs |
| BCM GPIO24 | FS1000A RF transmitter |
| BCM GPIO26 | LCD push button to ground |
| ADS1115 AIN0 | Aurel RF RSSI, provisional |
| Pico GP1-GP6 | IR transmitter outputs 1-6 |
| Wi-Fi `192.168.2.30:42101` | Tower Pico control |
| Wi-Fi `192.168.2.26:8765` | Remote aquarium temperature source |
