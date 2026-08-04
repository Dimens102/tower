# IR Learning Wizard

The IR learning wizard should create complete, useful device-database entries rather than only dumping raw pulse files.

## Interactive wizard

Start the recorder with:

```text
tower learn
```

The wizard asks for the manufacturer, the physical remote name, the logical
device name, its location, and its default transmitter. It then repeatedly asks
for a stable command name and a description. Leave the command name empty to
finish the device. Before each eight-second capture, the wizard waits until the operator
confirms that the remote is aimed at the receiver array.

Every successful recording also creates or updates the matching logical device
command. Until the completed IR transmitter array is installed and verified,
the default is the proven `Tower-IR-TX-001` output.

Change the routing for an already configured device with:

```text
tower device set <device> transmitter Tower-IR-TX-001
```

This updates all IR commands belonging to that device. The command-level
`transmitter` field remains available for a deliberate individual override.

New device captures are stored as:

```text
data/ir/devices/<Device name>/<Command>.ir
```

Existing records under `data/ir/remotes/<Name>/<Command>.ir` and
`data/ir/<Name>/<Command>.ir` remain readable for backward compatibility.

## Direct command

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

After every recording, the wizard prints the complete six-receiver analysis
table before deciding whether the command is clean enough to save. This makes
missing signals or a receiver that consistently reports no valid frames visible
while the remote is still being recorded.

## Wizard flow

```text
Manufacturer?
Remote name?
Device name?
Location?
Transmitter? [Tower-IR-TX-001]
Command name?
Description?
Press Enter when ready...
Press the same remote button several times...
```

Tower:

1. Verifies and initializes all six receivers.
2. Captures the signal simultaneously through the receiver array.
3. Detects a protocol when possible.
4. Validates the capture.
5. Atomically saves through the database layer.
6. Confirms the saved logical device and command.

Every `.ir` file contains the command description, winning capture metadata,
raw replay frame, and the complete six-receiver analyzer result with GPIO,
receiver model, nominal kHz, frame count, valid frame count, result, and decode.

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
- Manufacturer
- Physical remote name
- Logical device name
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
