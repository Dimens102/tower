# Device Database

The device database is Tower's source of truth for logical devices, commands, transports, aliases, and descriptive metadata.

## Storage

Each logical device is stored as one JSON file:

```text
data/devices/<device-id>.json
```

Tower uses `nlohmann::ordered_json` so fields are written in a stable, readable order.

The JSON library is vendored in the repository:

```text
external/nlohmann/json.hpp
```

## Current device model

Each device currently contains:

- `id`
- `name`
- `type`
- `manufacturer`
- `model`
- `location`
- `enabled`
- `aliases`
- `commands`

```cpp
class Device
{
public:
    std::string id;
    std::string name;

    std::string type;
    std::string manufacturer;
    std::string model;
    std::string location;

    bool enabled = true;

    std::vector<std::string> aliases;
    std::vector<DeviceCommand> commands;
};
```

## Current command model

Each command currently contains:

- `id`
- `name`
- `transport`
- `transportDevice`
- `transportCommand`
- `transmitter`
- `enabled`

Supported transport types currently are:

- `IR`
- `RF`

```cpp
enum class TransportType
{
    IR,
    RF
};

class DeviceCommand
{
public:
    std::string id;
    std::string name;

    TransportType transport = TransportType::IR;

    std::string transportDevice;
    std::string transportCommand;

    std::string transmitter;

    bool enabled = true;
};
```

Command aliases have not been implemented yet.

## Example device JSON

```json
{
    "id": "Denon",
    "name": "Denon",
    "type": "avr",
    "manufacturer": "Denon",
    "model": "AVR-X2800H",
    "location": "Living Room",
    "enabled": true,
    "aliases": [
        "Receiver",
        "Living Room Receiver"
    ],
    "commands": []
}
```

## Device identity

Each device has a stable internal ID that is independent of its display name, aliases, location, or physical implementation.

Automations and interfaces should reference the stable ID, not the current display name or filename.

## Device CLI

Implemented device operations:

```text
tower device list
tower device show <device-id>
tower device create <device-id>
tower device set <device-id> <property> <value>
tower device alias add <device-id> <alias>
tower device alias remove <device-id> <alias>
tower device delete <device-id>
```

The device command implementation is split into dedicated handlers:

```text
src/commands/device.cpp
src/commands/device_list.cpp
src/commands/device_show.cpp
src/commands/device_create.cpp
src/commands/device_set.cpp
src/commands/device_alias.cpp
src/commands/device_delete.cpp
```

## Commands

Examples of logical commands:

- `Power`
- `PowerOn`
- `PowerOff`
- `VolumeUp`
- `VolumeDown`
- `Mute`
- `HDMI1`
- `InputTV`

A command maps a logical operation to one transport implementation without exposing transport filenames to the automation engine.

Example logical reference:

```text
LivingRoomReceiver.Power
```

## Transport mappings

Initial transports:

- IR
- RF

Possible future transports:

- MQTT
- Zigbee
- HTTP
- Serial
- GPIO
- Bluetooth

Transport-specific details must remain isolated from generic device metadata.

## Replacement principle

Automations must reference the stable logical device and command.

When hardware is replaced, Tower should update the transport mapping in the device database rather than editing every automation, schedule, voice phrase, or client button.

## Next milestone

Implement command management inside each device:

```text
tower command list <device-id>
tower command show <device-id> <command-id>
tower command create <device-id> <command-id>
tower command set <device-id> <command-id> <property> <value>
tower command delete <device-id> <command-id>
```

The exact CLI syntax should be confirmed before implementation.
