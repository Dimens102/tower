# IR Learning Wizard

The IR learning wizard should create complete, useful device-database entries rather than only dumping raw pulse files.

## Command

Current minimal command:

```text
tower learn <device> <command>
```

Future interactive entry point:

```text
tower learn
```

## Proposed flow

```text
What type of device?
Manufacturer?
Model?
Friendly device name?
Location?
Which command are you recording?
Press the remote button now...
```

Tower then:

1. Initializes the receiver.
2. Captures the signal.
3. Detects a protocol when possible.
4. Validates the capture.
5. Saves through the database layer.
6. Confirms the saved logical device and command.

## Device types

Initial choices may include:

- TV
- AVR
- Media Player
- Projector
- Set-top box
- Air Conditioner
- Light
- Other

This list should remain extensible.

## Information to record

### Generic device fields

- Internal device ID
- Device type
- Manufacturer
- Model
- Friendly name
- Location
- Description or notes

### Command fields

- Stable command ID
- Friendly command name
- Description
- Repeat behavior

### Signal fields

- Protocol, when detected
- Scancode, when decoded
- Raw pulse data, when needed
- Carrier frequency, when known
- Repeat count
- Selected transmitter/output
- Capture date or format version, if useful

## Protocol strategy

Prefer decoded protocol and scancode data when reliable.

Retain raw capture support for:

- unknown protocols
- devices not decoded by the kernel
- signals requiring exact timing
- troubleshooting and fallback replay

Protocol detection, file/database storage, and physical capture should remain separate layers.

## Naming principle

Automations must not depend on paths such as:

```text
data/ir/Denon/Power.ir
```

They should use a logical identity such as:

```text
LivingRoomReceiver.Power
```
