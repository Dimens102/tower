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
