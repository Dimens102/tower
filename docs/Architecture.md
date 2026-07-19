# Tower Architecture

## Project rules

- Project name: Tower
- Executable name: `tower`
- Repository folder: `~/Development/rf-tower`
- GitHub repository: `https://github.com/Dimens102/tower`

## Architecture principles

- Keep hardware access hidden behind core classes.
- No subsystem should talk directly to Linux GPIO except the GPIO class.
- RF, IR, scheduling, web, and voice must remain separate modules.
- Compile after every meaningful code change.
- Commit only after a working milestone.
- Keep storage, protocol handling, and hardware access in separate layers.
- User interfaces must not contain automation logic.
- Automations must reference logical device commands, not filenames.
- New transports must be addable without redesigning the automation engine.
- CLI command groups should use small, dedicated handler files instead of monolithic implementations.

## Current core layers

```text
Tower CLI
  -> Command parser and command-group dispatchers
  -> Device Database / RFReceiver / IRReceiver / IRSender / future modules
  -> GPIO abstraction / LIRC abstraction
  -> libgpiod / Linux input / LIRC
  -> Linux hardware devices
```

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
- UI code must not perform GPIO or LIRC access directly.
