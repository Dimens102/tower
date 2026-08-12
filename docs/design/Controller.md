# Controller Design

## Status

**State:** Implemented

Tower distinguishes local hardware controllers from controllers reached through
a network:

```text
include/devices/controllers/
src/devices/controllers/
    Local controllers

include/devices/remote/controllers/
src/devices/remote/controllers/
    Network-connected controllers
```

Both use the common `Controller` runtime interface and therefore share the
`ManagedDevice` lifecycle.

## Current controllers

### ADS1115

The ADS1115 is a local I2C controller. It extends the Raspberry Pi with four
analogue input channels and currently provides RSSI measurements for RF work.

### Tower Pico

The Tower Pico is a remote controller implemented on a Raspberry Pi Pico 2 W.
It connects to the normal Wi-Fi network and listens at:

```text
192.168.2.30:42101
```

The Pico controls IR transmitter outputs GP1 through GP6. In Tower
configuration these are addressed as outputs 1 through 6.

The implementation lives in:

```text
include/devices/remote/controllers/pico_controller.h
src/devices/remote/controllers/pico_controller.cpp
```

The MicroPython firmware lives in:

```text
pico/main.py
pico/wifi_config.example.py
```

Wi-Fi credentials stay in the local, ignored `pico/wifi_config.py` file.

## Responsibilities

Controllers:

- initialize their hardware or connection;
- report whether they are available;
- expose hardware capabilities to higher-level Tower components;
- keep transport details out of IR, RF, and automation logic.

Controllers do not own application logic, schedules, or device commands.

## Pico command protocol

Tower opens a TCP connection to port `42101`, sends one newline-terminated
command, and reads one newline-terminated response.

Supported commands:

| Command | Response | Purpose |
|---|---|---|
| `PING` | `PONG` | Connectivity check |
| `STATUS` | `STATUS OUTPUTS=...` | Read output states |
| `ALL_OFF` | `OK ALL_OFF` | Return every output low |
| `TEST n` | `OK TEST n` | Briefly pulse output `n` |
| `SEND n k d1,d2,...` | `OK SEND n` | Send raw IR durations at carrier `k` kHz |

Raw duration values are alternating carrier-on and carrier-off times in
microseconds. Values must be between 1 and 100000. Carrier values must be
between 20 and 60 kHz. The earlier `SEND n d1,d2,...` form remains accepted
and uses 38 kHz for compatibility.

## IR transmitter routing

An IR transmitter definition chooses either a local GPIO or the remote Pico.

Local example:

```ini
gpio=23
```

Remote Pico example:

```ini
controller=tower-pico
output=1
```

`IRSender` routes the transmission based on these fields. Existing local LIRC
transmitters remain supported.

## Ownership

The Controller base participates in the managed-device architecture. The Pico
is currently instantiated on demand by `IRSender` because an IR send is a
request-driven operation rather than a continuously scheduled task.
