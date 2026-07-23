# Tower Architecture

## Project rules

- Project name: Tower
- Executable name: `tower`
- Repository folder: `~/Development/rf-tower`
- GitHub repository: `https://github.com/Dimens102/tower`

## Architecture principles

- Keep hardware access hidden behind core classes.
- No subsystem should talk directly to Linux GPIO except the GPIO class.
- RF, IR, sensors, scheduling, web, and voice must remain separate modules.
- Compile after every meaningful code change.
- Commit only after a working milestone.
- Keep storage, protocol handling, and hardware access in separate layers.
- User interfaces must not contain automation logic.
- Automations must reference logical device commands, not filenames.
- New transports must be addable without redesigning the automation engine.
- New sensors must be addable through the shared sensor interface.
- CLI command groups should use small, dedicated handler files instead of monolithic implementations.

## Current core layers

```text
Tower CLI
  -> Command parser and command-group dispatchers
  -> Device Database / SensorManager / RFReceiver / IRReceiver / IRSender
  -> Sensor drivers / GPIO abstraction / LIRC abstraction
  -> Bosch BME68x API / libgpiod / Linux input / LIRC / Linux I²C
  -> Linux hardware devices
```

## Current sensor architecture

```text
CLI / future scheduler / automation / web interface
                         |
                         v
                   SensorManager
                         |
             +-----------+-----------+
             |                       |
             v                       v
           BME688              Future sensors
             |
             v
       Bosch BME68x API
             |
             v
          Linux I²C
```

Sensor drivers implement the shared `Sensor` interface.

Each sensor provides:

- initialization;
- availability state;
- measurement updates;
- a stable sensor name;
- a `SensorReading` containing its latest values.

Current sensor files:

```text
include/sensors/sensor.h
include/sensors/sensor_reading.h
include/sensors/sensor_manager.h
include/sensors/bme688.h

src/sensors/sensor_manager.cpp
src/sensors/bme688.cpp
```

The current sensor CLI command is:

```text
tower sensor
```

It initializes the registered BME688 and reports:

- temperature in degrees Celsius;
- relative humidity;
- atmospheric pressure in hPa;
- gas resistance in ohms.

## Current device command structure

```text
src/commands/device.cpp
    -> device_list.cpp
    -> device_show.cpp
    -> device_create.cpp
    -> device_set.cpp
    -> device_alias.cpp
    -> device_delete.cpp
```

`device.cpp` is a dispatcher only. Each device subcommand has its own handler.

## Target architecture

```text
CLI / REST API / Web UI / Phone App / PC Integration
                         |
                         v
                 Tower daemon/service
                         |
             +-----------+-----------+
             |                       |
             v                       v
      Automation Engine         Device Service
             |                       |
             +-----------+-----------+
                         |
                         v
                  Device Database
                         |
         +---------------+----------------+
         |               |                |
         v               v                v
      IR Driver       RF Driver       Future Drivers
         |               |          MQTT / Zigbee / HTTP
         v               v          Serial / GPIO / Bluetooth
      LIRC/Linux       GPIO/Linux
```

## Layer responsibilities

### CLI and APIs

- Accept user or application requests.
- Validate input.
- Call service-layer operations.
- Contain no protocol encoding, GPIO handling, or scheduling logic.

### Tower daemon/service

- Own long-running state.
- Host the automation engine.
- Resolve and execute device commands.
- Expose APIs to interfaces.
- Maintain logs and execution history.

### Automation engine

- Own schedules, triggers, conditions, actions, delays, and retries.
- Execute logical commands such as:

```text
LivingRoomReceiver.Power
```

- Never execute data files directly.
- Remain independent of IR, RF, MQTT, Zigbee, or other transports.

### Device database

- Store stable logical device IDs.
- Store friendly names, type, manufacturer, model, and location.
- Store enabled state and aliases.
- Store device commands and their transport mappings.
- Persist logical devices as JSON under `data/devices/`.
- Allow hardware replacement without rewriting automation rules.

### Hardware drivers

- Handle physical capture and transmission.
- Handle protocol timing and operating-system integration.
- Contain no scheduling or UI logic.
- Remain replaceable behind Tower-owned interfaces.

### Sensor subsystem

- Keep sensor-specific driver code behind the shared `Sensor` interface.
- Let `SensorManager` own registered sensor instances and request updates.
- Expose normalized readings through `SensorReading`.
- Keep CLI, automation, display, and future API code independent of Bosch or Linux I²C details.
- Permit future sensors such as ADS1115-connected analogue sensors without changing consumers of sensor data.

## Persistent storage

Logical device records are stored as formatted JSON:

```text
data/devices/<device-id>.json
```

Tower uses the vendored JSON library from:

```text
external/nlohmann/
```

`nlohmann::ordered_json` is used so saved field order remains stable and readable.

## Command resolution example

```text
Automation:
  LivingRoomReceiver.Power
          |
          v
Device Database:
  Device = living_room_receiver
  Command = power
  Transport = IR
          |
          v
IR Sender:
  transmitter = front_ir
  protocol/raw data = resolved command data
          |
          v
LIRC / Linux
```

## Separation rules

- `main.cpp` remains a dispatcher only.
- Command-group dispatchers remain small.
- Core contains shared infrastructure only.
- Every subsystem gets its own directory.
- Third-party libraries stay under `external/` and remain hidden behind Tower interfaces.
- Persistent data stays under `data/`.
- Documentation stays under `docs/`.
- Device metadata must not be embedded in drivers.
- Protocol code must not perform database writes directly.
- Sensor drivers must not contain UI, scheduling, or automation logic.
- UI code must not perform GPIO, I²C, or LIRC access directly.


---

## v0.9.4 - ADS1115 Analogue Sensor Architecture

The sensor subsystem now supports both environmental sensors and generic analogue acquisition devices.

Current architecture:

```text
SensorManager
├── BME688
└── ADS1115
```

The ADS1115 is treated as a generic ADC rather than an RF-specific device. This allows future hardware (battery monitoring, light sensors, potentiometers, current sensors, RSSI, etc.) to reuse the same implementation.

The future RF receiver will consume two independent inputs:

```text
RF Receiver
├── GPIO DATA
└── ADS1115 RSSI
```

The ADS1115 remains independent from the RF subsystem and contains no RF protocol logic.
