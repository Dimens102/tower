# Device Database

The device database is Tower's source of truth for logical devices, commands, transports, and descriptive metadata.

## Device identity

Each device should have a stable internal ID independent of its friendly name or hardware implementation.

Suggested fields:

- `id`
- `friendly_name`
- `device_type`
- `manufacturer`
- `model`
- `location`
- `description`
- `tags`
- `enabled`

Example:

```text
id: living_room_receiver
friendly_name: Living Room Receiver
device_type: avr
manufacturer: Denon
model: AVR-X2800H
location: Living Room
```

## Commands

Commands belong to a logical device.

Examples:

- `Power`
- `PowerOn`
- `PowerOff`
- `VolumeUp`
- `VolumeDown`
- `Mute`
- `HDMI1`
- `InputTV`

A command should map to one transport implementation without exposing filenames to the automation engine.

Example logical reference:

```text
LivingRoomReceiver.Power
```

## Transport data

Initial transports:

- IR
- RF

Possible future transports:

- MQTT
- Zigbee
- HTTP
- Serial
- GPIO

Transport-specific fields should remain isolated from generic device metadata.

### IR examples

- protocol
- scancode
- raw pulses
- carrier frequency
- repeat count
- transmitter/output

### RF examples

- protocol/family
- transmitter ID
- unit
- pulse length
- repeat count
- GPIO
- pairing status

## Replacement principle

Automations must reference the stable logical device and command.

When hardware is replaced, update the database mapping rather than every automation rule.
