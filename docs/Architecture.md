# Tower Architecture

## Project rules

- Project name: Tower
- Executable name: tower
- Repository folder: ~/Development/rf-tower
- GitHub repository: https://github.com/Dimens102/tower

## Architecture principles

- Keep hardware access hidden behind core classes.
- No subsystem should talk directly to Linux GPIO except the GPIO class.
- RF, IR, scheduling, web, and voice must remain separate modules.
- Compile after every meaningful code change.
- Commit only after a working milestone.

## Current core layers

```text
Tower CLI
  -> Command parser
  -> RFReceiver / future modules
  -> GPIO abstraction
  -> libgpiod
  -> Linux GPIO device
