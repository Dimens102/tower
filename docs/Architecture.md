# Tower Architecture

## Project rules

- Project name: Tower
- Executable name: `tower`
- Repository folder: `~/Development/rf-tower`
- GitHub repository: `https://github.com/Dimens102/tower`

## Architecture principles

- Keep hardware access hidden behind core classes.
- No subsystem should talk directly to Linux GPIO except the GPIO class.
- RF, IR, sensors, scheduling, web, and voice must remain separate modules.
- Compile after every meaningful code change.
- Commit only after a working milestone.
- Keep storage, protocol handling, and hardware access in separate layers.
- User interfaces must not contain automation logic.
- Automations must reference logical device commands, not filenames.
- New transports must be addable without redesigning the automation engine.
- New sensors must be addable through the shared sensor interface.
- CLI command groups should use small, dedicated handler files instead of monolithic implementations.

## Current core layers

```text
Tower CLI
  -> Command parser and command-group dispatchers
  -> Device Database / SensorManager / RFReceiver / IRReceiver / IRSender
  -> Sensor drivers / GPIO abstraction / LIRC abstraction
  -> Bosch BME68x API / libgpiod / Linux input / LIRC / Linux I²C
  -> Linux hardware devices
```

## Current sensor architecture

```text
CLI / future scheduler / automation / web interface
                         |
                         v
                   SensorManager
                         |
             +-----------+-----------+
             |                       |
             v                       v
           BME688              Future sensors
             |
             v
       Bosch BME68x API
             |
             v
          Linux I²C
```

Sensor drivers implement the shared `Sensor` interface.

Each sensor provides:

- initialization;
- availability state;
- measurement updates;
- a stable sensor name;
- a `SensorReading` containing its latest values.

Current sensor files:

```text
include/devices/sensors/sensor.h
include/devices/sensors/sensor_reading.h
include/devices/sensors/sensor_manager.h
include/devices/sensors/bme688.h

src/devices/sensors/sensor_manager.cpp
src/devices/sensors/bme688.cpp
```

The current sensor CLI command is:

```text
tower sensor
```

It initializes the registered BME688 and reports:

- temperature in degrees Celsius;
- relative humidity;
- atmospheric pressure in hPa;
- gas resistance in ohms.

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

### Sensor subsystem

- Keep sensor-specific driver code behind the shared `Sensor` interface.
- Let `SensorManager` own registered sensor instances and request updates.
- Expose normalized readings through `SensorReading`.
- Keep CLI, automation, display, and future API code independent of Bosch or Linux I²C details.
- Permit future sensors such as ADS1115-connected analogue sensors without changing consumers of sensor data.

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
- Sensor drivers must not contain UI, scheduling, or automation logic.
- UI code must not perform GPIO, I²C, or LIRC access directly.


---

## v0.9.4 - ADS1115 Analogue Sensor Architecture

The sensor subsystem now supports both environmental sensors and generic analogue acquisition devices.

Current architecture:

```text
SensorManager
├── BME688
└── ADS1115
```

The ADS1115 is treated as a generic ADC rather than an RF-specific device. This allows future hardware (battery monitoring, light sensors, potentiometers, current sensors, RSSI, etc.) to reuse the same implementation.

The future RF receiver will consume two independent inputs:

```text
RF Receiver
├── GPIO DATA
└── ADS1115 RSSI
```

The ADS1115 remains independent from the RF subsystem and contains no RF protocol logic.


---

## Unreleased RF Monitor Checkpoint

The current unfinished RF diagnostics use two independent hardware inputs:

```text
Aurel RX-4MM5-F
├── DATA ──> Raspberry Pi GPIO4
└── RSSI ──> ADS1115 AIN0
```

The assignments above are provisional until the physical wiring is permanently documented.

The implementation currently has two experimental command paths:

```text
tower monitor
├── Count DATA edges during each one-second interval
└── ADS1115 initialized, but RSSI not yet sampled

tower receive
├── Read RSSI voltage from ADS1115 AIN0
└── Print time between DATA edges from GPIO4
```

This is a development checkpoint, not the final RF receiver architecture.

The intended completed flow remains:

```text
ADS1115 AIN0
    |
    v
Measure noise floor and detect RF energy
    |
    v
Open a capture window
    |
    +------ GPIO4 edge timestamps
    |
    v
Build one complete RF capture
    |
    v
Attach RSSI and timing metadata
    |
    v
Decode, compare, store, or replay
```

Architectural rules:

- The ADS1115 driver remains generic and contains no RF-specific logic.
- The RF receiver layer combines GPIO DATA with analogue RSSI.
- CLI commands should invoke RF receiver services rather than permanently owning capture logic.
- Pulse capture, protocol decoding, storage, and device mapping remain separate responsibilities.
- GPIO4 and AIN0 must eventually come from documented hardware configuration rather than being duplicated as hard-coded values.

---

# v0.10.0 - Service-Oriented Architecture

The Tower project now includes its first long-running execution engine. Rather than individual command implementations owning their own execution loops, background processing is now coordinated through a shared service architecture.

Current execution flow:

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

This architecture provides a common foundation for all long-running background functionality.

## Service Layer

The `TowerService` owns the lifetime of the application.

Responsibilities include:

- Constructing shared infrastructure.
- Registering managed devices.
- Starting the scheduler.
- Coordinating clean shutdown.

Future subsystems should integrate through the service layer rather than creating independent execution loops.

---

## Scheduler

The Scheduler is responsible for executing periodic background work.

Responsibilities:

- Register managed devices.
- Execute devices at configurable polling intervals.
- Own the shared timer infrastructure.
- Provide a single scheduling implementation for all background tasks.

The scheduler should remain independent from the specific work performed by managed devices.

---

## Device Manager

The DeviceManager owns all registered managed devices.

Responsibilities:

- Store managed devices.
- Initialize managed devices.
- Provide access to registered devices.
- Allow the scheduler to iterate over active devices.

Future managed devices should register through the DeviceManager instead of being managed directly by the service.

---

## ManagedDevice

The previous service abstraction named `Device` has been renamed to `ManagedDevice`.

This removes a naming conflict with the existing hardware `Device` model used by the device database.

Every managed device now follows the same execution model and can be scheduled uniformly.

Current managed devices:

```text
RemoteTemperatureSource
```

Future managed devices may include:

```text
BME688
RFReceiver
WeatherService
MQTTClient
HTTPDevice
```

---

## Logging Architecture

A reusable logging subsystem has been introduced.

Current design:

```text
TowerService
       |
       +------ Logger
                    |
          +---------+---------+
          |                   |
          v                   v
     Scheduler       ManagedDevice
                              |
                              v
                 RemoteTemperatureSource
```

The logger provides:

- timestamps;
- log levels;
- component names;
- thread-safe console output.

Subsystems should log through the shared Logger rather than writing directly to `std::cout`.

---

## HTTP Client

Network communication is now abstracted behind a reusable `HttpClient`.

Current flow:

```text
ManagedDevice
      |
      v
HttpClient
      |
      v
HTTP Server
```

The HTTP client currently supports HTTP GET requests and provides a reusable foundation for future REST integrations and remote hardware.

---

## Remote Temperature Source

The first managed device implemented using the new architecture is `RemoteTemperatureSource`.

Execution flow:

```text
Scheduler
      |
      v
RemoteTemperatureSource
      |
      v
HttpClient
      |
      v
Remote Raspberry Pi
      |
      v
TemperatureReading
```

The remote temperature source periodically retrieves JSON data over HTTP and converts it into a reusable `TemperatureReading`.

This demonstrates that both local and remote hardware can be integrated through the same managed-device architecture.

---

## Architectural Direction

The current service architecture is intended to become the foundation for future Tower subsystems including:

- local sensors;
- remote sensors;
- RF receiver;
- automation;
- REST API;
- web interface;
- MQTT;
- scheduled tasks.

All future long-running components should integrate through the shared service infrastructure instead of implementing independent execution loops.

## New Work Day block 26-7-2026 bellow

---

# Runtime Managed-Device Unification

Tower now uses one shared runtime lifecycle model for local sensors and remote
data sources.

This change unifies previously separate execution paths without replacing the
existing logical device database.

## Logical devices and runtime devices

Tower contains two distinct device concepts.

### Logical devices

Logical devices represent user-facing home-automation objects stored in the
device database.

Examples:

```text
LivingRoomReceiver
DellProjector
BedroomLight
```

Logical devices contain metadata, commands, aliases, and transport mappings.
They are persisted under:

```text
data/devices/
```

### Runtime managed devices

Runtime managed devices are live software components owned and executed by the
Tower service.

Examples:

```text
BME688
TemperatureSensor
```

They represent active local hardware, remote sources, or other long-running
service components.

The runtime managed-device framework does not replace the logical device
database. The two systems have different responsibilities.

## Shared lifecycle

All runtime managed devices derive from:

```text
ManagedDevice
```

The common lifecycle interface contains:

```cpp
initialize()
update()
available()
name()
```

This allows the service infrastructure to initialize, schedule, update, and
inspect different runtime components through one stable interface.

## Current hierarchy

```text
ManagedDevice
├── Sensor
│   └── BME688
└── RemoteSource
    └── TemperatureSensor
```

`Sensor` remains the shared interface for components that expose normalized
`SensorReading` data.

`RemoteSource` represents managed data sources whose values originate outside
the local Tower process.

## Runtime execution flow

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
    |
    +-------------------+
    |                   |
    v                   v
 Sensor            RemoteSource
    |                   |
    v                   v
 BME688        TemperatureSensor
```

The responsibilities are divided as follows:

### TowerService

- Owns the lifetime of the running Tower service.
- Constructs and connects shared runtime infrastructure.
- Registers runtime managed devices.
- Coordinates startup and clean shutdown.

### Scheduler

- Provides periodic execution for managed runtime work.
- Uses the shared timer infrastructure.
- Remains independent of individual sensor or source implementations.

### DeviceManager

- Owns registered `ManagedDevice` instances.
- Initializes managed devices.
- Updates managed devices.
- Exposes registered devices to the scheduler and diagnostic command paths.

### ManagedDevice implementations

- Hide implementation-specific hardware or communication details.
- Report whether they are currently available.
- Perform their own update operation.
- Expose a stable runtime name.

## SensorManager retirement

The previous `SensorManager` duplicated lifecycle responsibilities that now
belong to `DeviceManager`.

It has therefore been removed.

Before:

```text
SensorManager
├── BME688
└── ADS1115
```

After:

```text
DeviceManager
├── BME688
└── TemperatureSensor
```

The `tower sensor` diagnostic command now uses `DeviceManager` while continuing
to expose sensor readings through the shared `Sensor` interface.

## Completed migration

This architecture change completes the following work:

- Introduced `ManagedDevice` as the common runtime lifecycle abstraction.
- Made `Sensor` derive from `ManagedDevice`.
- Added `RemoteSource` as a managed runtime category.
- Renamed `RemoteTemperatureSource` to `TemperatureSensor`.
- Converted `TemperatureSensor` to the managed runtime lifecycle.
- Converted the BME688 to the managed runtime lifecycle.
- Migrated sensor ownership and updates to `DeviceManager`.
- Removed the obsolete `SensorManager`.
- Preserved the working `tower sensor` diagnostic command.
- Verified clean service startup and shutdown through `tower service`.

## Architectural boundary

This milestone intentionally does not yet integrate:

```text
ADS1115
PCF8574
RFReceiver
IRReceiver
RFSender
IRSender
```

Their exact runtime roles will be handled in a separate architecture milestone.

Long-running receivers may later participate in the managed runtime lifecycle.
Request-driven transmitters may remain transport services rather than being
forced into the same inheritance hierarchy.

This separation prevents unrelated hardware abstractions from being added to
the runtime hierarchy before their ownership and lifecycle requirements are
defined.

# Controller Runtime Category

The runtime architecture now distinguishes between hardware that produces measurements and hardware that provides infrastructure capabilities.

Current runtime hierarchy:

```text
ManagedDevice
├── Sensor
├── Controller
└── RemoteSource
```

## Sensor

Sensors represent devices whose primary responsibility is producing measurements from the physical world.

Examples:

- BME688
- Future environmental sensors

## Controller

Controllers represent hardware infrastructure devices that expose capabilities to the rest of the system.

Rather than representing environmental measurements, controllers provide additional hardware resources to the RadioTower platform.

Examples include:

- ADS1115 (analog inputs)
- PCF8574 (GPIO expansion)
- PCA9685 (PWM expansion)

Controllers participate in the same runtime lifecycle as all managed devices:

- initialize()
- update()
- available()
- name()

## ADS1115 Migration

The ADS1115 has been migrated from the `Sensor` runtime category into the new `Controller` category.

Although the ADS1115 performs analog-to-digital conversion, its primary role within the RadioTower project is extending the Raspberry Pi's hardware capabilities by providing additional analog input channels.

The ADS1115 currently supplies RSSI measurements for the RF receiver and serves as the first implementation of the Controller runtime category.

This migration establishes the architectural foundation for future hardware expansion devices while preserving the common ManagedDevice lifecycle.

---

# Temperature Source Architecture

Temperature access is divided by source while retaining one top-level command group:

```text
tower temperature local
    -> BME688
    -> Direct I2C measurement

tower temperature remote ID1
tower temperature remote aquarium
    -> TemperatureSensor
    -> HTTP measurement and stored hourly history
```

## Local temperature

The local command creates a BME688 instance and performs one forced measurement.

```text
Tower CLI
    |
    v
BME688
    |
    v
Linux I2C
    |
    v
Local temperature
```

`tower temperature local` displays only the temperature value.

The broader `tower sensor` diagnostic remains available for all BME688 measurements:

- Temperature
- Humidity
- Pressure
- Gas resistance

## Remote temperature

The remote temperature path uses the managed `TemperatureSensor`.

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
TemperatureSensor
    |
    v
HttpClient
    |
    v
Remote Raspberry Pi
```

The current remote source has:

```text
Permanent source ID : ID1
Friendly name       : aquarium
Hardware sensor ID  : 28-000008c84830
```

`ID1` is the permanent remote-source identifier.

`aquarium` is a friendly name and may be changed without changing the permanent identity of the source.

The remote source is polled every 30 seconds. Valid readings are cached and one history entry is stored per hour in:

```text
runtime/temperature/temperature_history.csv
```

The history retains up to 504 entries, representing three weeks at one entry per hour. The temperature command groups history entries by ISO week when displaying them.

## Service autostart

The operating-system service launches:

```text
tower service
```

during system boot.

This allows remote temperature polling and hourly history storage to continue without an interactive terminal or logged-in user.
