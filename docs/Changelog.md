# Tower Changelog

## v0.11.01 - Tower Control management and UI integration (2026-08-23)

### Added

- Added the Home page as the default Tower Control landing page with
  configurable IR-device artwork and direct remote opening.
- Added full Windows IR-device management including ordering, deletion,
  display-name rename, transmitter selection, learned-command rendering, and
  integrated IR learning/calibration workflows.
- Added six-receiver IR learning diagnostics and global duplicate detection.
- Added visible IR calibration tap/countdown progress and automatic wizard
  completion after a successful calibration save.
- Added RF power provisioning, pairing state, presets, deletion, and
  display-name rename from Tower Control.
- Added persistent Cards/List view selection for RF power devices.
- Added persistent sensor cards with an Aquarium image and Cards/List/Details
  layouts using the Settings-style view controls.
- Added the Raspberry Pi system clock to the Tower Control header.
- Added authenticated Pi API support required by the Windows management UI,
  including IR/RF rename and RF provisioning/management actions.

### Changed

- Tower Control startup now uses local IR and RF inventory caches so Home,
  IR Remotes, and RF Power can render before background synchronization.
- RF Power is pre-rendered from cache while the application is still hidden,
  eliminating the visible top-to-bottom control build during first tab access.
- Background IR/RF refreshes are cache-aware and quiet during startup; a
  transient read failure no longer unnecessarily replaces a usable cached view.
- Identical IR and RF inventory responses no longer rebuild already-rendered
  controls.
- Sensor refreshes update existing labels in place instead of clearing and
  rebuilding the entire Sensors page.
- Sensor Cards view stacks blocks vertically; List arranges the same full blocks
  horizontally; Details provides a compact tabular overview.
- Improved Tower Control header, clock, RF list spacing, button styling,
  remote-image handling, and sidebar/tab responsiveness.
- Updated the project and runtime version to `0.11.01`.

### Fixed

- Fixed startup RF and IR refresh races that could briefly show false red
  refresh-failure status messages.
- Fixed RF Power and Home controls flashing or rebuilding when switching tabs.
- Fixed PowerShell WinForms event-scope handling that prevented IR rename from
  returning the entered name.
- Restored the IR remote preview-heading callback removed during an earlier UI
  refactor.
- Restored the sensor refresh failure handler after the persistent-card
  conversion.
- Fixed RF list width resizing so the configured right-side spacing is not
  silently forced back to the old width.
- Preserved RF execution through the direct `RFCommandService` path instead of
  depending on a deleted executable or `/proc/self/exe`.

### Verified

- Learned IR commands can be captured, saved, rendered, and transmitted from
  the Windows application.
- RF controls remain responsive using the direct service path and cached UI.
- IR and RF display-name changes preserve their immutable internal record IDs.
- Home, Sensors, RF Power, and IR Remotes now reopen without unnecessary
  network refreshes or visible control reconstruction.

## v0.10.12 - IR learning and transmission calibration (2026-08-12)

### Added

- Added generic device-level IR transmission profiles with calibrated carrier,
  carrier duty, calibration command, and transmitter qualification results.
- Added per-transmitter duty overrides so a device can keep a conservative
  default duty while weaker physical outputs use a higher verified duty.
- Added confirmed transmitter qualification: `4/5` and `5/5` results are
  repeated, and only two clean `5/5` batches count as a verified pass.
- Added multi-transmitter calibration fallback that surveys all six IR outputs
  when the initially selected transmitter cannot produce a clean result.
- Added explicit experimental 70/80% fallback duty tests on only the best
  responding transmitter; normal automatic calibration remains capped at 60%.
- Added an end-of-wizard IR transmission calibration phase that uses five
  discrete test taps, detects over-triggering, searches the lowest reliable
  duty cycle, refines the carrier around the receiver-array candidate, and can
  qualify all six IR transmitters.
- Added capture metadata for initial and protocol repeat frames to newly learned
  IR recordings.
- Added interactive `tower learn` device recording wizard.
- Added per-command descriptions and automatic logical device-command updates.
- Added complete six-receiver analysis metadata to every newly learned IR file.
- Added the complete six-receiver analysis table to the terminal after every
  wizard recording, including recordings that fail validation.
- Added organized `data/ir/devices/<Device>/<Command>.ir` storage while keeping
  both earlier IR storage layouts readable.
- Added device-level manufacturer, physical remote name, location, and
  transmitter questions to the recording wizard.
- Added `tower device set <device> transmitter <value>` propagation to all IR
  commands on that device, while retaining command-level overrides.
- Added authenticated sensor snapshots for the aquarium sensor and every BME688
  measurement.
- Added authenticated logical-device discovery and command execution endpoints.
- Added one API action that switches every paired RF power device On or Off and
  returns the result for each device.
- Replaced the RF-only Windows remote with Tower Control, containing Sensors,
  RF Power, and dynamically discovered IR Remotes pages.
- Added combined All On and All Off buttons to the RF Power page.

### Changed

- The receiver selected by the six-receiver analyzer now supplies the initial
  carrier candidate for newly learned commands instead of relying only on a
  protocol-family carrier constant; runtime calibration can refine it.
- Runtime IR execution now applies the logical device's calibrated carrier and
  duty automatically while replay CLI carrier/duty options remain diagnostic
  overrides.
- Runtime duty resolution now prefers a CLI diagnostic override, then a
  transmitter-specific duty override, then the device default duty.
- Calibration batches now wait five seconds before transmission and send five
  taps one second apart for clearer human counting without making full
  qualification runs excessively slow.
- Carrier refinement reuses the already-proven center-carrier result and tests
  only adjacent `-1/+1 kHz` candidates; equal scores retain the center carrier.
- Transmitter qualification is treated as device/protocol-specific rather than
  assigning one global quality state to a physical IR output.
- Raised the Pico IR duty software ceiling to 80% for explicit experimental
  fallback testing. A 100% carrier duty remains intentionally unsupported.
- Siemens handset toggle state is no longer counted as a protocol repeat frame.
- New IR devices default to the proven `Tower-IR-TX-001` output. Combined-array
  transmission is deferred until the completed transmitter hardware is tested.
- Tower now sends each raw recording's stored `carrier_khz` value to the Pico,
  and the Pico selects that PWM carrier for the individual transmission.
  Recordings without carrier metadata retain the earlier 38 kHz default.

### Fixed

- Fixed Siemens/KPN Manchester captures that lost a final SPACE half-bit into
  the mode2 frame timeout, allowing previously rejected KPN commands such as
  Fast Forward to decode cleanly.
- Fixed Siemens toggle-bit handling so handset toggle state is not
  misclassified as a protocol repeat.
- Prevented transmitter qualification from immediately replacing a known-good
  profile because of one noisy five-shot result; proposed qualification data is
  now built before replacing the live profile.
- Detached the Tower Control GUI from its launcher console and made sensor unit
  symbols safe in Windows PowerShell.
- Improved the Refresh All button contrast in the dark header.

### Verified

- The complete Pi build linked successfully.
- The systemd service restarted with the new executable and served authenticated
  BME688 and aquarium sensor snapshots.
- RF and logical-device discovery returned the live configured devices.
- Combined All Off and All On controlled all six paired RF power devices.
- Tower Control displayed sensors, RF controls, and recorded IR commands on
  Windows without a visible launcher console.
- KPN Media Box commands decode and replay reliably at 56 kHz, including
  previously failing Siemens commands after Manchester end-half-bit
  reconstruction.
- Denon AVR-X2800H transmission was verified at 38 kHz / 40% device default on
  TX-001 and TX-004, with TX-005 using a verified 50% per-transmitter duty
  override.
- TX-006 was verified to work with KPN while remaining ineffective for Denon,
  demonstrating that physical-transmitter compatibility is device/protocol
  specific.
- Real-world Denon range testing showed that room reflections can materially
  affect apparent transmitter range; moving a projection sheet changed the
  available reflected path without any software or hardware failure.

## v0.10.10 - PC bridge RF execution correction

### Fixed

- Changed `POST /api/v1/rf/send` to launch the exact existing
  `tower send <device> <on|off>` command and wait for its exit status.
- The API now returns success only when the proven CLI command exits
  successfully; device and action values are validated before launch and no
  shell is used.
- Corrected the six RF button labels to their current uses and marked the DIY
  Buro Lamp as paired.

### Changed

- Updated the project and runtime version to `0.10.10`.

## v0.10.9 - First PC bridge and RF remote

### Added

- Added an authenticated LAN HTTP API to the existing `tower service` process.
- Added `GET /api/v1/rf/devices` to list RF devices from the existing
  `.rf` files, including their friendly `device_name` labels and stored status.
- Added `POST /api/v1/rf/send` to perform `on` and `off` actions through the
  same RF command service used by the existing CLI `send` command.
- Added a Windows PowerShell Forms remote that retrieves the RF device list
  from Tower and creates On/Off buttons dynamically.
- Added `%APPDATA%\Tower\client.json` storage for the PC address and API token.

### Changed

- Refactored `tower send <RF-device> <on|off>` to call the shared
  `RFCommandService`; its command syntax and RF sender remain unchanged.
- Updated the project and runtime version to `0.10.9`.

## v0.10.8 - Logical command execution

### Added

- Added a shared `CommandExecutor` that executes an already-resolved logical
  command through the existing IR or RF sender.
- Added structured execution results for future automation and HTTP API use.

### Changed

- Extended the existing `tower execute <device-id> <command-id>` resolver so it
  now transmits after displaying the stored mapping.
- Preserved `tower replay <device> <command> <transmitter>` for direct IR tests.
- Preserved `tower send <RF-device> <on|off>` for direct RF tests.
- IR execution uses the transmitter stored in the logical command mapping; no
  transmitter is hard-coded.
- Disabled devices and commands, incomplete mappings, invalid RF actions, and
  failed transport loads now return a non-zero exit code.
- Updated the runtime version to `0.10.8`.

## v0.10.7 - Successful IR receiver integration

### Added

- Added the six-receiver IR array with 30, 33, 36, 38, 40, and 56 kHz
  demodulating receivers.
- Added dynamic GPIO-to-`/dev/lircX` discovery through sysfs so changing Linux
  LIRC device numbers do not affect the configured receiver identities.
- Added `tower ir-receivers` to verify the complete array and show its current
  live LIRC mappings.
- Added `tower ir-capture` for synchronized raw capture through all six
  receivers.
- Added `tower ir-analyze` for native capture-group decoding and best-receiver
  selection.
- Added native Siemens/Ruwido, NEC, NECx, Sony SIRC-12, and
  Kaseikyo-Denon decoding.
- Added protocol, address, command, carrier, receiver, and source-capture
  metadata to newly learned raw IR records while preserving compatibility with
  existing `.ir` files.
- Added receiver discovery, capture subprocess, protocol decoder, receiver
  ranking, and IR database round-trip regression tests.

### Changed

- Replaced the old single-receiver raw learning path with synchronized
  six-receiver capture and analysis.
- `tower learn <device> <command> [seconds] [--force]` now requires a clean,
  stable supported decode, selects the best receiver, extracts one validated
  initial frame, and saves it atomically for replay.
- Existing learned commands are protected by default. Forced replacement only
  occurs after a successful capture and creates a `.tower-learn-backup` first.
- Silent receivers are reported as `NO-SIGNAL`; normal `mode2` startup
  diagnostics are no longer treated as capture errors.
- Updated the project and runtime version to `0.10.7`.

### Verified

- All six installed receivers resolve correctly despite reversed live LIRC
  numbering from `/dev/lirc5` through `/dev/lirc0`.
- A real KPN Power capture selected GPIO25 / TSOP38256 at 56 kHz and decoded
  12 of 12 frames as Siemens address `0x250`, command `0x0B`.
- Tower saved one validated 35-timing frame with complete decode and receiver
  metadata.
- `tower replay KPN PowerArrayTest Tower-IR-TX-001` successfully switched the
  KPN receiver off, proving capture, analysis, storage, loading, and replay
  compatibility end to end.
- The short transmission range was isolated to the unfinished transmitter
  array hardware and does not invalidate the receiver integration.

## Local display work (unreleased)

### Added

- Added an HD44780-compatible 20x4 LCD through an I2C backpack at address
  `0x27`.
- Added the normal status screen with room temperature, aquarium temperature,
  room humidity, and air pressure.
- Added GPIO26 push-button control for the LCD backlight.
- Added an ordered LCD startup sequence that reports the LCD, Raspberry Pi,
  sensors and scheduler, Tower Pico, and GPIO26 status before the normal
  display becomes active.
- Added a real Tower Pico startup health check using the existing TCP
  `PING`/`PONG` protocol at `192.168.2.30:42101`.
- Added an exclusive non-blocking service lock at
  `/tmp/rf-tower-service.lock` to prevent multiple `tower service` processes
  from controlling the same LCD and GPIO hardware.

### Changed

- A single button press enables the backlight for 30 seconds.
- A double press locks the backlight on; another double press switches it off.
- Added rising- and falling-edge handling to debounce the physical button.
- Shortened the Raspberry Pi startup label to `Raspberry PI 3 A+` so it fits
  on the display.
- Grouped each startup diagnostic as a clean `checking` followed by its result:
  sensors and scheduler, Tower Pico, then GPIO26.

### Verified

- The project builds successfully.
- Timed, permanently-on, and off backlight modes work through the running
  `rf-tower.service`.
- The systemd service retains the exclusive lock for its complete lifetime.
- A second `tower service` invocation exits immediately with
  `Tower service is already running; refusing to start another instance`
  before it can initialize the LCD or GPIO.
- The Tower Pico startup check reports the result of a real network
  `PING`/`PONG` transaction.

## v0.10.4

### Added

- Added the Pico 2 W as a Wi-Fi-connected remote Controller.
- Added `devices/remote/controllers/` for network-connected controller
  implementations.
- Added the TCP `PING` and raw IR `SEND` protocol on port `42101`.
- Added MicroPython firmware and a private Wi-Fi configuration template under
  `pico/`.
- Added fixed Tower routing to the reserved Pico address `192.168.2.30`.

### Changed

- Routed `Tower-IR-TX-001` through Pico output 1 / GP0.
- Extended IR transmitter records with `controller` and `output` fields while
  preserving local GPIO/LIRC transmitters.
- Made the executable select the Tower project root automatically so relative
  `data/` and `runtime/` paths work outside the project directory.
- Removed stale controller command and design documentation that had no matching
  v0.10.3 implementation.
- Updated the project version to `0.10.4`.

## v0.10.3

- Restructured the source and header trees into dedicated `core/` and `devices/` categories.
- Moved command handling, logging, networking, and service components under `core/`.
- Moved controller, IR, RF, and sensor components under `devices/`.
- Updated include paths, namespaces, and documentation for the new structure.
- Expanded the command documentation with the currently supported and verified commands.
- Added a CMake installation rule for installing `tower` as a system command.
- Verified installation to `/usr/local/bin/tower` using `cmake --install build`.
- Synchronized the project and runtime version as `0.10.3`.

## v0.10.2

### Added

- Introduced the `Controller` runtime category.
- Added the `Controller` base class derived from `ManagedDevice`.
- Added controller design documentation.

### Changed

- Migrated `ADS1115` from the `Sensor` runtime category to the new `Controller` runtime category.
- Moved ADS1115 source files from `devices/sensors/` to `devices/controllers/`.
- Updated all references, namespaces, and include paths.

### Verified

- Project builds successfully.
- Environmental sensor functionality remains operational.
- ADS1115 monitoring continues to function correctly for RF RSSI measurements.

### Architectural Result

The runtime architecture now distinguishes between hardware that measures the physical environment (`Sensor`) and hardware that extends or controls platform capabilities (`Controller`).

This establishes the foundation for future controller implementations while preserving the common `ManagedDevice` lifecycle.

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

## v0.9.4

- Added ADS1115 analogue-to-digital converter support.
- Extended the generic SensorReading model with analogue channel support.
- SensorManager now supports both environmental and analogue sensors.
- Added four-channel voltage reporting to the `tower sensor` command.
- Verified simultaneous operation of:
  - ADS1115 (0x48)
  - BME688 (0x76)
- Prepared the architecture for future RF RSSI integration without coupling RF logic into the ADC driver.

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
- Added dedicated `include/devices/sensors/` and `src/devices/sensors/` directories.
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

## v0.10.4

### Added

- Added the Raspberry Pi Pico 2 W as a Wi-Fi-connected remote Controller.
- Added `devices/remote/controllers/` for network-connected controller implementations.
- Added TCP communication using `PING` and raw IR `SEND` commands on port `42101`.
- Added Pico MicroPython firmware under `pico/main.py`.
- Added `pico/wifi_config.example.py` for local Wi-Fi configuration.
- Added Tower routing to the reserved Pico address `192.168.2.30`.

### Changed

- Routed `Tower-IR-TX-001` through Pico output 1 / GP0.
- Extended IR transmitter records with `controller` and `output` fields while preserving local GPIO/LIRC transmitters.
- Made Tower automatically locate the project root so `data/` and `runtime/` work when Tower is started outside the project directory.
- Removed stale PCF8574/controller documentation that had no matching implementation in v0.10.3.
- Updated the Tower version to `0.10.4`.
