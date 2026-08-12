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

## Transmission calibration

After command learning, Tower can calibrate the physical transmission profile
for the logical device. The learned `.ir` files remain signal recordings; the
runtime transmission calibration is stored on the device as `irProfile`.

The device profile can contain:

- calibrated carrier frequency
- default carrier duty
- calibration command
- verified transmitters
- unreliable transmitters
- incompatible transmitters
- per-transmitter duty overrides

Runtime duty resolution is:

```text
CLI diagnostic --duty override
    -> per-transmitter duty override
    -> device default duty
```

Carrier is currently device-level. Command-level carrier/duty overrides remain
available through `tower replay` for diagnostics.

### Human-assisted calibration

Tower has no feedback channel from the controlled appliance, so the operator is
the sensor. Use a command where one transmission creates one clearly countable
action, for example `Volume Up`, `Volume Down`, `Temp Up`, or `Temp Down`.

A calibration batch:

1. Prints the transmitter, carrier, and duty being tested.
2. Waits 5 seconds so the operator can prepare.
3. Sends five discrete taps, one second apart.
4. Asks how many device actions occurred.

Qualification rules:

- `0-3/5`: clear failure; move to the next candidate.
- `4/5` or `5/5`: repeat the same setting for confirmation.
- Only `5/5` followed by `5/5` is a clean verified pass.
- More than five observed actions means over-triggering and that test setting
  is rejected.
- Marginal results do not overwrite an already verified transmitter setting.

The normal automatic duty search is:

```text
33% -> 40% -> 50% -> 60%
```

The lowest duty that produces two clean `5/5` batches is preferred.

### Carrier refinement

The receiver selected by the six-receiver analyzer provides the initial carrier
candidate. After the center carrier passes, Tower tests the adjacent carrier
candidates (`-1 kHz` and `+1 kHz`). The center carrier is not transmitted a
second time merely to repeat an already known result.

If adjacent carriers score equally, Tower retains the analyzer/center carrier
rather than pretending one frequency was uniquely better.

### Multi-transmitter fallback

A device may respond very differently to the six physical IR outputs. A
transmitter that is excellent for one protocol can be poor for another.

If the initially selected transmitter cannot produce a confirmed pass in the
normal `33-60%` range, Tower surveys all six transmitter outputs at the current
carrier and 60% duty. The output with the strongest observed response becomes
the fallback calibration transmitter.

Tower then tests the center carrier and its adjacent `-1/+1 kHz` candidates on
that transmitter.

Only if no clean result is found does the wizard offer an explicit experimental
high-duty test:

```text
70%
80%
```

The experimental test is limited to the best responding transmitter instead of
driving all six outputs at high duty.

`100%` duty is intentionally unsupported. A 100% PWM duty has no carrier
off-time and therefore no longer represents normal modulated IR carrier
operation. The present transmitter board's actual peak LED current has also not
yet been instrumented, so 70/80% remain experimental rather than a guaranteed
electrical operating point.

### Profile persistence

Six-transmitter qualification is transactional: Tower builds the proposed
qualification result first and only replaces the device's previous transmitter
classification after the complete qualification run finishes.

This prevents a partial or cancelled calibration from destroying a previously
verified transmission profile.

Example proven Denon AVR-X2800H profile:

```text
Device default: 38 kHz / 40%

Tower-IR-TX-001 -> verified at device default
Tower-IR-TX-004 -> verified at device default
Tower-IR-TX-005 -> verified with 50% per-transmitter duty override
```

Physical room geometry still matters. A transmitter may pass by direct line of
sight yet lose room-bounce range when a reflective wall or projection surface
is moved. Calibration therefore records transmitter/device compatibility, not
a universal optical-range guarantee.

