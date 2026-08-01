# IR Learning Wizard

The IR learning wizard should create complete, useful device-database entries rather than only dumping raw pulse files.

## Command

Current validated receiver-array command:

```text
tower learn <device> <command>
```

Optional capture duration and protected replacement:

```text
tower learn <device> <command> [seconds] [--force]
```

Learning captures all six receivers simultaneously, decodes every recording,
selects the best clean protocol-matched receiver, and saves one validated raw
initial frame for replay. The saved `.ir` file also records the decoded
protocol, address, command, carrier, receiver, and source capture directory.

An existing command is never changed unless `--force` is supplied. Forced
replacement first creates a `.tower-learn-backup` copy. Failed or unsupported
captures remain under `captures/ir/` for analysis and do not change the command
database.

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

Tower currently:

1. Verifies and initializes all six receivers.
2. Captures the signal simultaneously through the receiver array.
3. Detects a protocol when possible.
4. Validates the capture.
5. Atomically saves through the database layer.
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
