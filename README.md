# Current Development Status

The core execution engine is now in place. The project currently supports:

- Scheduler
- Callback system
- Timer infrastructure
- One-shot timers
- Repeating timers
- DeviceManager framework
- AutomationEngine framework
- IR transmission
- RF transmission
- IR reception

These components provide the shared foundation for the remaining Tower features.

## Current Hardware Status

### RF Receiver

RF transmission is fully operational.

Reliable RF reception remains under active development.

The receiver currently generates a very large number of signal edges, making reliable recording difficult.

Several approaches have been investigated, including the manufacturer's recommended filtering. While this greatly reduces unwanted edges, it also significantly reduces reception quality and therefore is not considered a suitable solution.

The current direction is to use the receiver's RSSI output as a gate. Recording will begin only while RSSI indicates an active transmission and automatically stop once the signal disappears. This should greatly reduce background noise while still capturing complete RF transmissions.

### IR Transmitter

IR transmission is functional but currently does not match the performance of inexpensive commercial battery-powered remotes.

Several resistor configurations have been tested. The best-performing design so far uses dual 120 Ω resistors together with dual 1 kΩ resistors, producing reliable direct line-of-sight operation.

Commercial remotes are still capable of operating devices using reflected IR from walls, while Tower generally requires a much more direct optical path.

Further hardware optimisation of the IR transmitter remains an ongoing task.

## Temperature and Sensor Support

Environmental monitoring is operational through both local and remote temperature sources.

The Tower's locally connected **BME688** provides:

- Temperature
- Humidity
- Air pressure
- Gas resistance

The remote **TemperatureSensor** retrieves aquarium temperature measurements from a Raspberry Pi 2B over HTTP. It is configured with:

- Permanent source ID `ID1`
- Friendly name `aquarium`
- DS18B20 hardware sensor ID `28-000008c84830`
- A 30-second polling interval
- Hourly history storage under `runtime/temperature/`
- A maximum history of 504 hourly readings, representing three weeks

The long-running Tower service polls the remote sensor and maintains its history. The operating-system service starts Tower automatically during system boot.

Current temperature commands:

```text
tower temperature local
tower temperature remote ID1
tower temperature remote aquarium
```

The local command reads the BME688 directly. Both remote identifiers resolve to the same source. ID1 is the permanent identifier and remains stable if the friendly name changes.

See docs/Commands.md for the complete Tower command reference.

## Project Philosophy

The remaining RF receiver and IR transmitter improvements are considered hardware refinement tasks rather than blockers.

Development of the overall Tower platform—including automation, scheduling, sensors, networking, voice control and user interfaces—will continue while these hardware improvements are investigated in parallel.

---

# Service Infrastructure

The project now includes the first version of the long-running Tower execution engine.

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
ManagedDevice instances
```

The service owns the application's lifetime while the scheduler periodically updates registered managed devices.

## Scheduler

The Scheduler provides a common execution framework for long-running background tasks.

Current responsibilities:

- Register managed devices.
- Execute devices at configurable polling intervals.
- Own the shared TimerManager.
- Eliminate the need for individual command loops inside device implementations.

This scheduler will become the foundation for future:

- automation;
- periodic sensor polling;
- scheduled tasks;
- background services.

## Managed Devices

The original service abstraction named `Device` has been renamed to `ManagedDevice`.

This avoids a naming conflict with the existing hardware `Device` model used by the device database.

Every managed device now exposes a common lifecycle and can be registered with the `DeviceManager` for automatic scheduling.

Current managed devices:

- BME688
- ADS1115
- PCF8574
- TemperatureSensor (`ID1`, friendly name `aquarium`)

Future managed devices may include:

- BME688 environmental sensor
- RF receiver
- Weather services
- MQTT clients
- Additional network-connected sensors

## Logging

A reusable logging subsystem has been introduced.

Current features include:

- timestamped messages;
- log levels;
- component names;
- thread-safe console output.

The logger is intended to become the standard logging interface for all Tower subsystems.

## HTTP Networking

Tower now includes a reusable HTTP client built on libcurl.

Current capabilities:

- HTTP GET requests;
- response retrieval;
- error reporting.

The HTTP client is designed for reuse by future REST clients, remote sensors, web integrations and network-connected devices.

## Remote Temperature Source

The first network-connected managed device has been implemented.

`RemoteTemperatureSource` periodically retrieves JSON temperature data from a Raspberry Pi over HTTP.

This demonstrates that Tower can integrate remote hardware while exposing the data through the same managed-device architecture that will also support local hardware.

## Current Development Focus

With the core execution engine now operational, development can continue toward:

- shared sensor framework;
- local BME688 integration;
- Automation Engine expansion;
- additional managed devices;
- REST API;
- Web interface.