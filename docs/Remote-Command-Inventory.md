===== docs/Adding-Hardware.md =====
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
===== docs/Architecture.md =====
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
src/core/commands/device.cpp
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

===== docs/Automation-Engine.md =====
# Automation Engine

The Tower daemon should own automation execution. Web, phone, and desktop interfaces should only edit or invoke automation objects.

## Responsibilities

The automation engine should manage:

- schedules
- triggers
- conditions
- actions
- delays
- retries
- logging
- enabled/disabled state
- execution history

## Action model

An action should target a logical device command:

```text
LivingRoomReceiver.Power
```

The engine asks the device database to resolve that command. The database selects the transport and driver.

The automation must not execute data files directly:

```text
send data/ir/Denon/Power.ir
```

## Suggested automation object

```text
id
name
description
enabled
trigger
conditions
actions
created_at
updated_at
```

## Trigger examples

- specific time
- recurring schedule
- sunrise or sunset
- incoming API request
- RF or IR event
- GPIO state
- device state change
- future sensor event

## Condition examples

- day of week
- time range
- device state
- presence
- sensor threshold
- another automation state

## Action examples

- execute a logical device command
- wait
- execute a command again
- update state
- call an internal API
- run another automation

## Interface boundary

The web interface and phone app should:

- create and edit devices
- create and edit automations
- show state and history
- request command execution

They should not implement scheduling, conditions, protocol encoding, or hardware access.

===== docs/Changelog.md =====
# Tower Changelog

## v0.7.0

- Replaced the custom `.device` key/value format with JSON device records.
- Added vendored `nlohmann/json` 3.12.0 under `external/nlohmann/`.
- Added ordered JSON output for stable, readable device files.
- Added the structured `Device` model.
- Added the structured `DeviceCommand` model.
- Added persistent device aliases.
- Implemented device list, show, create, set, alias, and delete commands.
- Split device CLI operations into dedicated handler source files.
- Reduced `device.cpp` to a command dispatcher.
- Verified JSON persistence with the Denon and TV device records.

## v0.6.0

- Implemented real GPIO chip opening through libgpiod.
- Implemented real GPIO input request.
- Implemented real GPIO read.
- Confirmed Tower can read GPIO23.

## v0.5.0

- Expanded GPIO interface.
- Added RFReceiver skeleton.

## v0.4.0

- Added GPIO abstraction.

## v0.3.0

- Main command handling now uses command parser.

## v0.2.0

- Added command parser.

## v0.1.0

- Initial Tower project skeleton.
- Added CMake build.
- Added first tower executable.

===== docs/Device-Database.md =====
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
src/core/commands/device.cpp
src/core/commands/device_list.cpp
src/core/commands/device_show.cpp
src/core/commands/device_create.cpp
src/core/commands/device_set.cpp
src/core/commands/device_alias.cpp
src/core/commands/device_delete.cpp
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

===== docs/IR-Learning-Wizard.md =====
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

===== docs/Project-Goals.md =====
# Tower Project Goals

Tower is a Raspberry Pi-based home automation controller for transmitting,
receiving, scheduling, and remotely activating IR and RF commands.

This document records the intended end-state of the project and the priority
in which major capabilities should be implemented.

## Priority order

The numbered goals below are ordered by importance.

Development should first establish the shared foundations required by all
goals, but user-facing functionality should then be implemented in this order.

## 1. IR and RF learning and playback

Tower must be able to:

- Receive and record IR signals.
- Receive and record RF signals.
- Identify decoded protocol data when reliable.
- Retain raw signal data when decoding is unavailable or unsuitable.
- Store learned signals as commands belonging to logical devices.
- Replay stored IR commands.
- Replay stored RF commands.
- Select the correct physical transmitter or output.
- Validate learned commands through test playback.
- Replace or relearn a command without breaking schedules or remote controls.

Examples:

```text
LivingRoomReceiver.Power
KPNReceiver.Button1
Projector.PowerOn
BedroomLight.On
```

Logical device and command names must not depend on physical filenames,
GPIO numbers, transmitter hardware, or protocol implementation.

## 2. Rules, schedules, and action sequences

Tower must execute actions automatically based on time, sensor values, or
other conditions.

Examples:

```text
If temperature is at least 24 C:
    Send AirConditioner.PowerOn
```

```text
At 07:30:
    Send KPNReceiver.PowerOn
    Send KPNReceiver.Button1
    Send LivingRoomReceiver.PowerOn
    Send DellProjector.PowerOn
```

The automation system must eventually support:

- Time-based schedules.
- Sensor-value conditions.
- Multiple conditions.
- Delays between actions.
- Ordered action sequences.
- Enable and disable controls.
- Manual execution.
- Logging of every execution and result.
- Protection against repeatedly triggering the same rule.
- Future expansion to additional condition and action types.

The first automation-engine implementation may execute logical commands
without a scheduler. Scheduling and sensor-triggered evaluation can then be
added on top of that engine.

## 3. Control from the main PC

A small desktop control program must be able to command Tower over the local
network.

The PC interface should:

- Display selected devices and commands.
- Send logical commands rather than raw protocol data.
- Show whether Tower accepted and executed a command.
- Allow devices and buttons to be configured without changing program code.
- Be replaceable later without changing Tower's internal database.

The first client may be created using a simple Windows-compatible technology.
The network protocol must not depend on VBScript or any specific client
implementation.

Tower should expose a stable authenticated API that can also be used by future
desktop applications.

## 4. Voice control

Tower must support local voice commands through a connected microphone.

The voice-control system should:

- Recognize an explicit wake word or activation phrase.
- Avoid reacting to television, movies, music, or ordinary conversation.
- Map spoken phrases to logical Tower commands.
- Request confirmation for dangerous or ambiguous actions when appropriate.
- Allow aliases and natural phrases for devices and commands.
- Continue to function locally when practical.
- Keep speech recognition separate from the command-execution engine.

Example:

```text
"Tower, turn on the projector"
```

maps to:

```text
DellProjector.PowerOn
```

Voice recognition is an input method. It must use the same command API as the
PC and phone clients.

## 5. Remote phone control

Tower must be controllable from a phone, including from outside the home
network.

The phone interface should eventually support:

- A configurable selection of devices and commands.
- Manual command execution.
- Command status and recent history.
- Viewing sensor readings.
- Enabling and disabling schedules.
- Creating or editing schedules, if this can be done safely and clearly.
- Secure authentication.
- Encrypted communication.
- Restricted external exposure.

Tower may listen on a configured network port, but direct internet exposure
must be designed securely. Port forwarding alone must not be treated as
sufficient security.

The phone application must use the same stable API as other clients.

## 6. Local display

A display connected to the Raspberry Pi should normally show environmental
and system information such as:

- Time.
- Temperature.
- Humidity.
- Air pressure.
- Tower status.

When Tower receives, learns, or transmits a command, the display should
temporarily show relevant event information, such as:

- Device.
- Command.
- Transport.
- Protocol.
- Transmitter.
- Success or failure.

After a configurable delay, the display should return to its normal
information screen.

The display is an output interface and should consume Tower events rather
than being directly coupled to IR or RF code.

# Required shared architecture

The six goals require the following shared layers.

## Logical device database

The device database is the source of truth for:

- Stable device IDs.
- Friendly names.
- Device types.
- Manufacturer and model.
- Location.
- Enabled state.
- Commands and capabilities.
- Voice aliases.
- UI visibility.
- Transport mappings.

A logical command should resolve to a transport-specific implementation.

Example:

```text
LivingRoomReceiver.PowerOn
    -> transport: IR
    -> stored signal: denon_x2800_power_on
    -> transmitter: living_room_ir
```

## Transport backends

Transport-specific storage and transmission remain separate.

Initial transports:

- IR.
- RF.

Possible future transports:

- GPIO.
- HTTP.
- MQTT.
- Serial.
- Zigbee.

Existing IR and RF database code may be retained or modified as transport
backends underneath the logical device database.

## Sensor registry

Sensors require stable logical identities similar to controllable devices.

Examples:

```text
LivingRoom.Temperature
LivingRoom.Humidity
LivingRoom.Pressure
```


===== docs/Remote-Command-Inventory.md =====
# Remote Command Inventory

This document contains the current inventory of physical remotes that
will be supported by the Tower project.

## Eurom PAC 7.2 Air-conditioner

-   Power On/Off
-   Speed
-   Temp Up
-   Temp Down
-   Mode
-   Timer

## Logitech Z5500 Sound Control Center

-   Test
-   Direct
-   Optical
-   Coax
-   Effect
-   Settings
-   Sub Up
-   Sub Down
-   Center Up
-   Center Down
-   Surround Up
-   Surround Down
-   Mute
-   Volume Up
-   Volume Down

## Dell 1610HD Projector

-   Power On/Off (1x = On, 2x = Off)
-   Arrow Up
-   Arrow Left
-   Arrow Right
-   Menu
-   Aspect Ratio
-   Zoom In
-   Zoom Out
-   Angle Up Forward
-   Angle Down Forward
-   Page Up
-   Page Down
-   Source
-   Auto Adjust
-   Black Screen
-   Video Mode

## Sony KDL-40Z4500 TV (RM-ED012)

-   Source
-   Info
-   Guide
-   Options
-   Home
-   Return
-   Digital
-   Analogue
-   Audio
-   Aspect Ratio
-   0-9
-   Teletext
-   Heart
-   Mute
-   Volume Up
-   Volume Down
-   Program Up
-   Program Down

## Denon AVR-X2800H

### General

-   Power On
-   Power Off
-   Volume Up
-   Volume Down
-   Mute
-   Page Up
-   Page Down
-   Option
-   Setup
-   Back
-   HDMI Out
-   Sleep

### User Inputs

-   KPN TV
-   Main PC
-   Intel NUC
-   ASUS NUC

### Original Inputs

-   CBL/SAT
-   MediaPlayer
-   Blu-ray
-   Game
-   Aux1
-   Aux2
-   TV Audio
-   CD
-   Tuner
-   USB
-   Phono
-   Bluetooth
-   HEOS
-   Internet Radio

### Sound Modes

-   Movie
-   Music
-   Game
-   Pure

## LED Light Strip

-   On
-   Off
-   25%
-   50%
-   75%
-   100%
-   Fade
-   60S Countdown
-   15M Countdown
-   30M Countdown
-   60M Countdown
-   Up
-   Down

## LED Light Bar

-   Brightness Up
-   Brightness Down
-   On
-   Off
-   Red
-   Green
-   Blue
-   White
-   RGB Mode
-   Strobe Mode
-   Fade Mode
-   Smooth Mode
-   12 Colour Buttons

## Generic 3-Way HDMI Switch

-   Channel 1
-   Channel 2
-   Channel 3

## KPN Non-Recorder Media Box

### Media

-   Power On/Off
-   Fast Backward
-   Fast Forward
-   Pause/Play
-   Stop
-   Record

### Colour Buttons

-   Red
-   Green
-   Yellow
-   Blue

### Navigation

-   Arrow Up
-   Arrow Down
-   Arrow Left
-   Arrow Right
-   OK
-   Menu
-   TV Quick Menu
-   Radio
-   Back / Last Channel
-   Program Up
-   Program Down

### Numeric

-   0-9

### Other

-   Teletext

## RF Remotes

All RF remotes have already been recorded and verified.

## Future Notes

Potential future command fields: - aliases - repeatCount -
repeatDelayMilliseconds - holdMilliseconds
===== docs/RF-Protocols.md =====
# RF Protocol Notes

This document records RF families, timing assumptions, pairing behavior, and verification status.

## Current scope

Tower currently supports stored RF power-device definitions and transmission through the RF sender layer.

## Device record fields

Current records may include:

- model or record ID
- protocol/family
- transmitter ID
- unit
- GPIO
- pairing status
- pulse length
- repeat count
- friendly device name

## Modern KAKU / M2 family

Known working family defaults currently used:

```text
pulse=260
repeat=16
```

These values may be inherited by an unpaired device record to keep the family configuration consistent.

Inherited values must not be described as individually verified until the physical receiver has been paired and tested.

### Current verification note

`Tower-RF-Power-M2-004` uses inherited M2-family timing values. They should be verified once the spare receiver is paired.

## Documentation rule

For every supported RF family, record:

- protocol/family name
- required addressing fields
- known pulse ranges
- repeat behavior
- pairing procedure
- tested transmitters and receivers
- exceptions or device-specific timing
- verification status

## Layering

RF protocol encoding belongs in the RF driver/protocol layer.

Friendly names, locations, and logical commands belong in the device database.

Automation rules should never contain transmitter IDs, raw timings, or GPIO details directly.

===== docs/Roadmap.md =====
# Tower Roadmap

> Last updated: 2026-07-19

---

# Vision

Tower is a modular, database-driven home automation platform.
Tower should become the central system that controls, monitors, and automates devices through multiple hardware interfaces while remaining hardware-independent through clean driver abstractions.
The project is built around small reusable modules instead of one large application.

---

# Foundation

Status: 88%
[x] Git repository
[x] CMake build system
[x] Versioning
[x] Command parser
[x] GPIO abstraction
[x] GPIO input
[x] GPIO edge events
[x] Vendored JSON library
[x] Modular device command handlers
[ ] GPIO output
[ ] Driver Manager
[ ] Logging system
[ ] Configuration system
[ ] Tower daemon/service
[ ] Persistent schema/version handling

---

# Drivers

Status: 25%

## GPIO

[x] Input
[x] Edge detection
[ ] Output
[ ] PWM

## SPI

[ ] Generic SPI driver

## I²C

[ ] Generic I²C driver

## UART

[ ] Generic UART driver

## Bluetooth

[ ] Bluetooth manager
[ ] HID keyboard
[ ] HID media remote

---

# Radio

Status: 45%

## 433 MHz RF

[x] Basic receiver
[x] RF transmission
[x] Stored RF device definitions
[ ] Pulse capture
[ ] Pulse timing analysis
[ ] Noise filtering
[ ] Packet detection
[ ] Protocol detection
[ ] Verify `Tower-RF-Power-M2-004` after pairing

## 868 MHz

[ ] CC1101 driver

## IR

[x] Receiver framework
[x] Raw IR capture
[x] Start-of-frame filtering
[x] Pulse validation and timeout handling
[x] IR replay
[x] Multiple LIRC transmitters
[x] Kernel-decoded IR learning
[x] Raw IR learning
[x] IR database save path
[x] Verified Denon recordings
[x] Re-learned Logitech Z5500 power command
[ ] Interactive learning wizard
[ ] Protocol-aware storage with raw fallback
[ ] IR database load/list/remove commands
[ ] Carrier-frequency handling where supported

---

# Protocols

Status: 20%

## RF

[ ] PT2262
[ ] EV1527
[ ] HT6P20
[x] Stored family-specific timing values
[ ] Raw pulse format
[ ] Protocol verification tooling

## IR

[x] Kernel-decoded NEC learning path
[x] Raw pulse fallback
[ ] NEC userspace decoder
[ ] RC5
[ ] RC6
[ ] Sony
[ ] Panasonic
[ ] Protocol/scancode normalization

---

# Device Database

Status: 65%
[x] Persistent RF device files
[x] Persistent IR command files
[x] Friendly device metadata in RF records
[x] IR command save path
[x] Stable logical device IDs
[x] Friendly device names
[x] Device type
[x] Manufacturer
[x] Model
[x] Location
[x] Enabled state
[x] Device aliases
[x] JSON device persistence
[x] Device list command
[x] Device show command
[x] Device create command
[x] Device set command
[x] Device alias add/remove commands
[x] Device delete command
[x] Structured command objects inside devices
[x] Transport type field
[x] Transport device mapping field
[x] Transport command mapping field
[x] Transmitter field
[ ] Command CRUD CLI
[ ] Command aliases
[ ] Tags and descriptions
[ ] Database validation
[ ] Database migrations/versioning
[ ] Device replacement without editing automations

---

# Device Library

Status: 15%

## Current devices

[x] Denon AVR IR recordings
[x] Logitech Z5500 IR power recording
[x] Modern KAKU RF power devices
[ ] Eurom Arico
[ ] KPN TV
[ ] Dell 1610HD

## Future

[ ] Weather stations
[ ] PIR sensors
[ ] Temperature sensors
[ ] Relays
[ ] Light switches

---

# Automation

Status: 0%
[ ] Tower daemon/service
[ ] Scheduler
[ ] Event system
[ ] Rules engine
[ ] Conditions
[ ] Actions
[ ] Scenes
[ ] Delays and retries
[ ] Execution logging
[ ] Notifications
[ ] Device state model
Automations must use logical identities such as:
```text
LivingRoomReceiver.Power
```
They must not directly execute files such as:
```text
data/ir/Denon/Power.ir
```

---

# Interfaces

Status: 5%
[x] Command Line
[ ] REST API
[ ] Web Interface
[ ] Mobile Interface
[ ] PC Integration
[ ] Authentication and user accounts
Interfaces should edit and invoke Tower objects. They must not contain scheduling, protocol, or hardware-access logic.

---

# Future Transports

[ ] MQTT
[ ] Zigbee
[ ] HTTP devices
[ ] Serial devices
[ ] Direct GPIO devices
[ ] Bluetooth devices

---


---

# tower sensor

Status: Working

The `tower sensor` command now reports all registered sensors.

Current output includes:

- BME688
  - Temperature
  - Humidity
  - Pressure
  - Gas Resistance

- ADS1115
  - AIN0 Voltage
  - AIN1 Voltage
  - AIN2 Voltage
  - AIN3 Voltage

Future revisions will attach logical names to analogue channels (for example RF RSSI or Battery Monitor) while keeping the ADS1115 driver generic.


---

# tower monitor

Status: Work in progress

The unfinished `tower monitor` command is registered in the command parser and main dispatcher.

Current provisional hardware mapping:

```text
RF DATA = GPIO4
RF RSSI = ADS1115 AIN0
```

Current behavior:

- Opens `/dev/gpiochip0`.
- Initializes the ADS1115.
- Requests rising and falling edge events on GPIO4.
- Counts GPIO edges.
- Prints the number of detected edges once per second.

Current limitation:

Although the command initializes the ADS1115 and identifies AIN0 as the RSSI input, it does not yet read or display the RSSI voltage. The local RSSI variable is currently unused.

The command is therefore a basic digital activity monitor, not yet a complete RF signal monitor.

Planned completion:

- Continuously sample AIN0.
- Establish a noise-floor baseline.
- Display current, peak, and average RSSI.
- Detect the beginning and end of an RF transmission.
- Count and buffer edge timings during the detected transmission.
- Produce a capture summary.
- Pass complete captures to the future RF learning and decoding layer.

---

# tower receive - local RF diagnostic changes

Status: Work in progress

The local `tower receive` implementation has been extended beyond its earlier GPIO-edge test.

Current provisional hardware mapping:

```text
RF DATA = GPIO4
RF RSSI = ADS1115 AIN0
```

Current behavior:

- Initializes the ADS1115.
- Opens `/dev/gpiochip0`.
- Requests both edge types on GPIO4.
- Reads and prints AIN0 voltage as RSSI.
- Prints the interval between consecutive GPIO edges in microseconds.

This is still diagnostic output only. It does not yet:

- Frame a complete RF transmission.
- Maintain an RSSI noise floor.
- Apply signal-strength thresholds.
- Buffer or save pulse trains.
- Store RSSI metadata.
- Decode a protocol.
- Create a reusable learned RF command.

The final responsibility split between `tower monitor`, `tower receive`, and a future RF learning command must be decided when development resumes.
