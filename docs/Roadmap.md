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

# Current Milestone

Build logical command management and connect device commands to the existing IR and RF databases.
Current focus:
```text
Complete structured device database
        |
        v
Implement command CRUD
        |
        v
Resolve command transport mappings
        |
        v
Build shared command execution path
        |
        v
Integrate device-oriented IR learning
```

---

# Current Development Rules

- `main.cpp` is a dispatcher only.
- Command-group source files are dispatchers only.
- Each subcommand should use a dedicated handler where practical.
- Core contains only shared infrastructure.
- Every subsystem gets its own directory.
- Third-party libraries stay under `external/` and remain hidden behind Tower interfaces.
- Build after every meaningful change.
- Every commit must compile.
- Commit only after a working milestone.
- Freeze completed subsystems unless fixing bugs.
- Store persistent data under `data/`.
- Prefer device-oriented commands over file-oriented commands.
- Keep protocol decoding, storage, and hardware access separate.
- Record whether values are tested, inherited, or provisional.
- Update documentation when an architectural decision changes.

---

# Completed Recent Milestones

[x] Add IR replay with multiple LIRC transmitters
[x] Add kernel-decoded IR learning support
[x] Improve raw IR learning and pulse capture
[x] Add verified Denon and Logitech IR recordings
[x] Remove temporary IR test recording
[x] Update RF power device metadata
[x] Replace `.device` files with JSON
[x] Vendor `nlohmann/json`
[x] Add structured logical device model
[x] Implement complete device CRUD CLI
[x] Add device aliases
[x] Split device CLI into modular handlers

---

# Ideas Parking Lot

## Architecture

- Hierarchical CLI:
  - `tower ir learn`
  - `tower ir send`
  - `tower rf learn`
  - `tower weather read`
- Driver manager
- Plugin architecture
- Internal event bus
- Database schema versioning

## Radio

- CC1101 support
- Receiver comparison tool
- Radio diagnostics
- Signal verification/replay comparison

## Bluetooth

- HID media remote
- BLE support

## User Interface

- Web dashboard
- REST API
- Mobile application
- Device and automation editors

## Development

- Unit tests
- Integration tests with captured signals
- Configuration editor
- `tower status` command
- `tower devices list`
- `tower commands list`
- Structured logging
- Backup/export of the Tower database


---

# Preserved RF Monitor Work in Progress

The unfinished RF monitor implementation has been preserved as a local checkpoint so development can resume later without losing the experiment.

Completed in the checkpoint:

[x] Register `tower monitor`.
[x] Dispatch `tower monitor` from the CLI.
[x] Open the GPIO chip.
[x] Request both edge types on provisional GPIO4.
[x] Count RF DATA edges per second.
[x] Initialize the ADS1115 from the RF diagnostic commands.
[x] Read provisional RSSI input from ADS1115 AIN0 in `tower receive`.
[x] Report pulse intervals in microseconds in `tower receive`.

Required when development resumes:

[ ] Confirm and document the final RF DATA GPIO.
[ ] Confirm and document the Aurel ENABLE connection.
[ ] Move hardware assignments into configuration.
[ ] Add RSSI sampling to `tower monitor`.
[ ] Measure the idle noise floor.
[ ] Determine reliable start and end thresholds.
[ ] Capture complete pulse trains.
[ ] Correlate pulse data with RSSI measurements.
[ ] Generate capture summaries.
[ ] Persist learned captures and metadata.
[ ] Detect repeated frames.
[ ] Add protocol identification and decoding.
[ ] Decide the final roles of monitor, receive, and learn commands.
[ ] Refactor experimental command-loop logic into the RF receiver subsystem.
