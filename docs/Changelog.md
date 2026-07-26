# Tower Changelog

## v0.9.3

- Added the `tower sensor` command.
- Added the generic `Sensor` interface.
- Added `SensorReading` for temperature, humidity, pressure, gas resistance, validity, and timestamps.
- Added `SensorManager` for sensor registration, initialization, updates, and reading access.
- Added BME688 environmental sensor support over Linux I²C.
- Vendored the official Bosch BME68x Sensor API under `external/bme68x/`.
- Verified live BME688 readings for temperature, humidity, pressure, and gas resistance.
- Verified the BME688 at I²C address `0x76` on the Raspberry Pi 3 A+.

## v0.9.2

- Added the initial sensor subsystem structure.
- Added dedicated `include/sensors/` and `src/sensors/` directories.
- Added the sensor interface, reading model, manager, and BME688 wrapper skeleton.
- Isolated sensor hardware access behind Tower-owned classes.

## v0.9.1

- Modernized the CMake project configuration.
- Added recursive source and header discovery with `CONFIGURE_DEPENDS`.
- Added explicit C and C++ project languages.
- Added project version metadata.
- Added private include directories and target-based library linking.
- Added automatic compilation of new source files placed under `src/`.

## v0.9.0

- Removed static `/dev/lircX` device configuration from IR transmitter records.
- Added runtime LIRC-device discovery based on the configured transmitter GPIO.
- Kept transmitter definition files limited to physical hardware metadata.
- Verified multiple LIRC transmitters without hard-coded Linux device numbers.

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


## v0.9.4

- Added ADS1115 analogue-to-digital converter support.
- Extended the generic SensorReading model with analogue channel support.
- SensorManager now supports both environmental and analogue sensors.
- Added four-channel voltage reporting to the `tower sensor` command.
- Verified simultaneous operation of:
  - ADS1115 (0x48)
  - BME688 (0x76)
- Prepared the architecture for future RF RSSI integration without coupling RF logic into the ADC driver.


## v0.10.0

- Added the long-running `TowerService` execution engine.
- Added the `Scheduler` for periodic execution of managed devices.
- Added the reusable `Callback` framework.
- Added the `Timer` class.
- Added the `TimerManager`.
- Added the `DeviceManager` for registration and management of background devices.
- Renamed the service abstraction from `Device` to `ManagedDevice` to avoid a naming conflict with the existing hardware `Device` model.
- Added the centralized `Logger` subsystem with timestamps, log levels and component names.
- Added the reusable `HttpClient` based on libcurl.
- Added the `TemperatureReading` model.
- Added the `RemoteTemperatureSource` managed device.
- Added periodic HTTP polling of a remote Raspberry Pi temperature sensor.
- Verified JSON temperature retrieval over HTTP.
- Established the first service-oriented execution architecture for long-running background components.

---

---

## RF monitor work in progress (unreleased)

This checkpoint preserves the unfinished RF receiver diagnostics work for later development.

Implemented locally:

- Added command registration and dispatch for `tower monitor`.
- Added an initial RF monitor command using `/dev/gpiochip0`.
- Configured the provisional RF DATA input as GPIO4 with rising and falling edge detection.
- Configured the provisional RSSI source as ADS1115 channel AIN0.
- Added one-second GPIO edge-count reporting to the monitor command.
- Extended `tower receive` to initialize the ADS1115, read AIN0, and report RSSI voltage.
- Extended `tower receive` to report elapsed microseconds between consecutive GPIO edges.

This work is intentionally unfinished and is not assigned a release version yet.

Still required:

- Sample and report RSSI inside `tower monitor`.
- Establish and measure the RSSI noise floor.
- Define signal-start and signal-end thresholds.
- Buffer complete pulse trains instead of printing individual intervals only.
- Associate RSSI measurements with each capture.
- Store capture metadata and pulse data.
- Add protocol detection or decoding.
- Replace provisional hard-coded GPIO and ADS1115 channel assignments with documented configuration.
- Confirm the final Aurel RX-4MM5-F ENABLE wiring.
- Add clean shutdown and capture summaries.

## v0.10.1

### Runtime managed-device unification

This release completes the migration from the dedicated sensor lifecycle to the
shared managed-device architecture.

#### Added

- Introduced `ManagedDevice` as the common runtime lifecycle abstraction.
- Added `RemoteSource` as a managed runtime category.
- Introduced a shared runtime lifecycle for both local and remote data sources.

#### Changed

- `Sensor` now derives from `ManagedDevice`.
- `BME688` now participates in the shared managed-device lifecycle.
- `RemoteTemperatureSource` has been renamed to `TemperatureSensor`.
- `TemperatureSensor` now derives from `RemoteSource`.
- `DeviceManager` now owns initialization and updates of managed runtime devices.
- The `tower sensor` command now uses `DeviceManager` instead of a dedicated sensor manager.

#### Removed

- Removed the dedicated `SensorManager`.
- Removed the duplicate sensor lifecycle implementation.

#### Verified

The following functionality was verified after the migration:

- Clean project compilation.
- `tower sensor` successfully reports:
  - BME688 temperature
  - BME688 humidity
  - BME688 pressure
  - BME688 gas resistance
  - ADS1115 analogue voltages
- `tower service` starts and shuts down correctly.
- No remaining references to `SensorManager` exist in the source tree.

#### Architectural result

The runtime hierarchy is now:

```text
ManagedDevice
├── Sensor
│   └── BME688
└── RemoteSource
    └── TemperatureSensor
```

This milestone establishes a single lifecycle model for long-running runtime
components while keeping the logical `Device` database architecture unchanged.

## v0.10.2

### Added

- Introduced the `Controller` runtime category.
- Added the `Controller` base class derived from `ManagedDevice`.
- Added controller design documentation.

### Changed

- Migrated `ADS1115` from the `Sensor` runtime category to the new `Controller` runtime category.
- Moved ADS1115 source files from `sensors/` to `controllers/`.
- Updated all references, namespaces, and include paths.

### Verified

- Project builds successfully.
- Environmental sensor functionality remains operational.
- ADS1115 monitoring continues to function correctly for RF RSSI measurements.

### Architectural Result

The runtime architecture now distinguishes between hardware that measures the physical environment (`Sensor`) and hardware that extends or controls platform capabilities (`Controller`).

This establishes the foundation for future controller implementations such as the PCF8574 and PCA9685 while preserving the common `ManagedDevice` lifecycle.

### Temperature commands and persistent remote history

#### Added

- Added `tower temperature local` for a direct BME688 temperature reading.
- Added `tower temperature remote <ID or name>` for remote temperature readings and history.
- Added permanent remote source ID `ID1`.
- Added friendly remote source name `aquarium`.
- Added `TemperatureHistory` with hourly CSV storage.
- Added week-grouped temperature history output.
- Added `docs/Commands.md` as the full-name Tower CLI reference.

#### Changed

- Updated the Tower autostart service so the long-running `tower service` process starts during system boot and continuously polls the remote source.
- Extended the temperature command handler to validate and route `local` and `remote` arguments.
- Configured remote temperature history to retain up to 504 hourly readings.

#### Verified

- `tower temperature local` reports the Tower's local BME688 temperature.
- `tower temperature remote ID1` reports the aquarium temperature and stored history.
- `tower temperature remote aquarium` resolves to the same permanent source as `ID1`.
- Remote temperature history continues to populate while the Tower service runs.