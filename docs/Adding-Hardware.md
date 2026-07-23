# Adding Hardware

This document describes the standard procedure for adding new hardware to the Tower project.

---

# IR Transmitters

## 1. Connect the hardware

Connect the IR LED to the desired transmitter circuit and note the GPIO pin.

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
| status | active / inactive |

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

| Name | GPIO | Device |
|------|-----:|--------|
| Tower-IR-TX-001 | 22 | Large Clear IR LED |
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
