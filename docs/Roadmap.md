# Tower Roadmap

> Last updated: 2026-08-13

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
[x] Driver Manager
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

[x] ADS1115 controller
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
[x] Six-frequency receiver-array discovery
[x] Synchronized six-receiver capture
[x] Native protocol decoding and best-receiver selection
[x] Protocol-aware metadata with raw replay compatibility
[x] End-to-end array learning and replay verification
[x] Interactive learning wizard
[ ] IR database load/list/remove commands
[x] Carrier-frequency handling where supported

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
[x] NEC and NECx userspace decoder
[ ] RC5
[ ] RC6
[x] Sony SIRC-12
[x] Panasonic/Kaseikyo-Denon
[x] Siemens/Ruwido
[x] Protocol/scancode normalization for supported protocols

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

Status: 30%
[x] Tower daemon/service
[x] Scheduler
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

Status: 45%
[x] Command Line
[x] REST API
[ ] Web Interface
[ ] Mobile Interface
[x] PC Integration
[ ] Authentication and user accounts
Interfaces should edit and invoke Tower objects. They must not contain scheduling, protocol, or hardware-access logic.

---


## Windows Control Application v2

Status: 5%

The Windows client is being promoted from a simple command sender to Tower's
primary desktop control surface. Tower remains the source of truth and the
Windows application must use the shared Tower API rather than implementing IR,
RF, scheduling, or device-storage logic locally.

### Phase 1 - Stability and sidebar shell

[ ] Diagnose and fix the recurring HTTP 400/stale-service failure.
[ ] Add client-side health checking and useful error diagnostics.
[ ] Recover/reconnect automatically where safe instead of requiring manual service restarts.
[ ] Implement a hidden right-edge sidebar window.
[ ] Support multiple monitors and allow the user to choose the target monitor.
[ ] Slide the sidebar out when the mouse reaches the selected monitor's right edge.
[ ] Default the open width to approximately one third of the selected monitor.
[ ] Add persistent UI settings for target monitor, sidebar width, hide delay, and appearance.
[ ] Load device and command data dynamically from Tower.

### Phase 2 - Remote-control interface

[ ] Show an image of the original physical remote on the left side of the panel.
[ ] Support transparent-background remote artwork.
[ ] Show Tower command buttons on the right side of the panel.
[ ] Group commands into useful categories.
[ ] Arrange related controls spatially where practical, for example Volume Up above Volume Down.
[ ] Give buttons clear pressed/held visual feedback.
[ ] Support press-and-hold/repeat behavior for suitable commands such as Denon volume.
[ ] Add per-device IR transmitter selection.
[ ] Always show transmitter selectors TX-001 through TX-006.
[ ] Allow one or more transmitter selectors to be active at the same time.
[ ] Visually distinguish selected and unselected transmitters.
[ ] Do not hide unavailable/experimental transmitters; the user must still be able to see all six.
[ ] Add custom action/macro buttons below the normal remote controls.
[ ] Allow a custom action to execute a command a configured number of times, for example Volume Up x10.
[ ] Add device/profile deletion from the Windows application with confirmation.
[ ] Refresh the client after a device/profile is deleted from Tower.

### Phase 3 - Programs, automation, and visual polish

[ ] Add a Programs tab.
[ ] Create, edit, enable, disable, and delete time-based programs from Windows.
[ ] Store and execute programs on the Raspberry Pi, not on the Windows PC.
[ ] Programs must reference logical Tower devices and commands.
[ ] Support ordered command sequences and repeat counts.
[ ] Prepare program/action definitions for later voice-command mapping.
[ ] Add RF command icons/thumbnails to improve visual recognition.
[ ] Add configurable sidebar colors and visual theme settings.
[ ] Track all Windows-client design decisions and implementation progress in `docs/Windows-Control-App.md`.

### Later voice integration

[ ] A separate voice-processing Raspberry Pi may perform speech recognition and intent detection.
[ ] Voice processing must invoke the same logical Tower command API as the Windows client.
[ ] Do not duplicate IR/RF protocol knowledge inside the voice-processing node.


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
[x] Integrate the six-frequency IR receiver array
[x] Decode and rank receiver-array captures natively
[x] Connect receiver-array capture and analysis to `tower learn`
[x] Verify learned-command replay on the real KPN receiver
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

---

# Service Infrastructure Milestone (Completed)

This milestone established the long-running execution framework that future Tower subsystems will build upon.

Completed:

[x] TowerService
[x] Scheduler
[x] Callback framework
[x] Timer
[x] TimerManager
[x] DeviceManager
[x] ManagedDevice framework
[x] Centralized Logger
[x] Reusable HttpClient
[x] TemperatureReading model
[x] RemoteTemperatureSource
[x] Remote HTTP temperature polling

Current architecture:

```text
TowerService
    |
    v
Scheduler
    |
    v
DeviceManager
    |
    v
ManagedDevice
```

The Scheduler now periodically executes registered managed devices, allowing both local and remote hardware to operate through the same execution framework.

The first managed device is:

```text
RemoteTemperatureSource
```

Future managed devices will include:

- BME688
- RF Receiver
- Weather services
- MQTT clients
- HTTP devices

---

# Next Milestone

Status: 20%

## Sensor Framework

[ ] Migrate local sensors to the ManagedDevice framework
[ ] Integrate the local BME688
[ ] Create a shared sensor registration system
[ ] Add sensor history
[ ] Prepare sensor events for the Automation Engine

This milestone will complete the transition from individual sensor implementations to a unified service-based sensor architecture.

---

# Runtime Managed-Device Migration (Completed)

This milestone completed the migration of the local sensor subsystem into the
shared managed-device architecture.

Completed:

[x] Introduce `ManagedDevice` as the common runtime lifecycle abstraction.
[x] Convert the `Sensor` hierarchy to the managed-device lifecycle.
[x] Convert the BME688 to a managed device.
[x] Introduce the `RemoteSource` runtime category.
[x] Rename `RemoteTemperatureSource` to `TemperatureSensor`.
[x] Migrate sensor ownership to `DeviceManager`.
[x] Remove the legacy `SensorManager`.
[x] Preserve the existing `tower sensor` diagnostics.

Current runtime hierarchy:

```text
ManagedDevice
├── Sensor
│   └── BME688
└── RemoteSource
    └── TemperatureSensor
```

This milestone intentionally does **not** include:

- Controller abstraction
- ADS1115 migration to Controller
- RF receiver integration
- IR receiver integration (completed in v0.10.7)

Those changes are reserved for the next architectural milestone to keep this
commit focused on lifecycle unification only.
