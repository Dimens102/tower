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

## Sensor Development

Environmental monitoring will be implemented incrementally.

The first sensor device will be a **RemoteTemperatureSource**, retrieving temperature measurements from a Raspberry Pi 2B over HTTP while maintaining a local cache and historical database.

The second planned sensor device is a locally connected **BME688**, providing measurements including:

- Temperature
- Humidity
- Air pressure
- Air quality

Both local and remote sensors will be managed through the same DeviceManager infrastructure.

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

- RemoteTemperatureSource

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