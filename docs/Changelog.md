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
