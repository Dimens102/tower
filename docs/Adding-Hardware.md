# Adding Hardware

This document describes the standard procedure for adding new hardware to the Tower project.

---

# Tower Pico remote controller

The Pico 2 W setup, fixed address, firmware upload, power wiring, and output
mapping are documented in
[`Pico-Remote-Controller.md`](Pico-Remote-Controller.md).

---

# IR Transmitters

## 1. Connect the hardware

Connect the IR LED to the desired transmitter circuit and note either the
Raspberry Pi GPIO or Tower Pico output.

## 2. Create the transmitter definition

Create a new file:

```
data/ir/transmitters/Tower-IR-TX-XXX.irtx
```

Example:

```ini
name=Tower-IR-TX-003
device_name=Small Clear IR LED
hardware=ID3
gpio=25
status=active
```

Required fields:

| Field | Description |
|-------|-------------|
| name | Unique transmitter name |
| device_name | Physical description of the emitter |
| hardware | Hardware identifier |
| gpio | BCM GPIO number |
| controller | Remote controller name; currently `tower-pico` |
| output | Remote controller output number |
| status | active / inactive |

For a transmitter connected to the Pico, use:

```ini
controller=tower-pico
output=1
```

Tower Pico outputs 1 through 6 map to GP1 through GP6.

## Notes

Do **not** add:

```ini
lirc_device=
```

The Tower software automatically discovers the correct `/dev/lircX` device at runtime based on the configured GPIO.

The `.irtx` files only describe the hardware.

---

# Testing

Replay a known-good command.

Example:

```bash
./build/tower replay Denon VolumeUp Tower-IR-TX-003
```

If the transmitter does not work:

1. Check wiring.
2. Verify the GPIO number.
3. Check the LED using a phone camera.
4. Replace the emitter with a known-good clear IR LED.
5. Test again.

If the replacement LED works, the original component is likely not a standard IR transmitting LED.

---

# Current Verified Configuration

| Name | Output | Device |
|------|--------|--------|
| Tower-IR-TX-001 | Tower Pico 1 / GP1 | Left IR Blaster |
| Tower-IR-TX-002 | 23 | Small Clear IR LED |
| Tower-IR-TX-003 | 25 | Small Clear IR LED |
| Tower-IR-TX-004 | 20 | Small Black IR LED *(hardware verified, emitter not compatible for Denon testing)* |
| Tower-IR-TX-005 | 21 | Medium Black IR LED *(hardware verified, emitter not compatible for Denon testing)* |

---

# Future

This document will later be expanded with procedures for:

- IR Receivers
- RF Transmitters
- RF Receivers
- Environmental Sensors
- Relays
- Other Tower hardware

---

# ADS1115 (Verified)

## Hardware

Verified I²C address:

```text
0x48
```

Current implementation:

- Four single-ended analogue input channels.
- Generic ADC driver for Tower.
- Shared by future hardware requiring analogue measurements.

The ADS1115 is intentionally independent of protocol implementations. Future RF receivers, battery monitors, light sensors and similar devices should reuse this driver rather than implementing their own analogue conversion logic.

Future planned use:

- RF RSSI
- Battery monitoring
- Current sensing
- Analogue sensors

# Remote Controllers

Remote controllers are separate devices that control Tower hardware over the network.

Their Tower implementations belong under:

```text
include/devices/remote/controllers/
src/devices/remote/controllers/
Tower Pico 2 W
```

The Tower Pico 2 W connects to the normal Wi-Fi network and accepts commands from Tower over TCP.

Current connection:

Address: 192.168.2.30
Port:    42101
Name:    tower-pico

The Pico initially receives an address through DHCP. Reserve 192.168.2.30 for it in the router and then reboot the Pico.

# Firmware files:

pico/main.py
pico/wifi_config.example.py
pico/wifi_config.py

wifi_config.py contains the private Wi-Fi credentials and must not be committed to GitHub.

Current output mapping:

Pico output	Pico GPIO
1	GP1
2	GP2
3	GP3
4	GP4
5	GP5
6	GP6

A transmitter using the Pico must contain:

controller=tower-pico
output=1

Do not add a Raspberry Pi gpio value to a Pico-controlled transmitter.

When externally powered:

Connect regulated adapter +5 V to Pico VSYS (physical pin 39).
Connect adapter ground to a Pico GND pin.
Power the transmitter board from the same adapter.
Keep a shared ground between the Pico and transmitter circuit.
Do not connect the adapter's +5 V to the Raspberry Pi 5 V rail.

Full setup and firmware-upload instructions are documented in:

[`Pico-Remote-Controller.md`](Pico-Remote-Controller.md)
