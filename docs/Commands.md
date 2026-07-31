# Tower Command Reference

This document uses the complete executable name `tower`. Personal shell shortcuts and aliases are intentionally excluded.

Run `tower` without arguments to display the program's built-in usage summary.

## Install the Latest Build

~~~bash
sudo cmake --install build
~~~

Run this from the Tower project directory after a successful build.

It installs the latest compiled executable as `/usr/local/bin/tower`, allowing `tower` to run from any directory.


## Temperature

### Read the Tower's local temperature

```bash
tower temperature local
```

Reads the locally connected BME688 over I2C and prints its current temperature.

This is a direct measurement and does not display remote temperature history.

### Read a remote temperature source by permanent ID

```bash
tower temperature remote ID1
```

Displays the latest reading and stored hourly history for remote source `ID1`.

The source currently represents the aquarium DS18B20 sensor.

### Read a remote temperature source by friendly name

```bash
tower temperature remote aquarium
```

Resolves the friendly name `aquarium` to permanent source `ID1` and produces the same result as the ID-based command.

Current remote source:

| Permanent ID | Friendly name | Hardware sensor ID |
|---|---|---|
| `ID1` | `aquarium` | `28-000008c84830` |

`ID1` is the permanent internal identity. The friendly name can be changed later without changing the source identity.

## Service

```bash
tower service
```

Starts the long-running Tower execution engine in the foreground.

The service owns the scheduler and managed runtime devices, including the remote temperature source.

The installed operating-system service runs this command automatically during system boot. This allows remote polling and hourly history collection to continue without an interactive terminal.

## Sensors

```bash
tower sensor
```

Runs the current sensor diagnostics.

It initializes the BME688 and ADS1115 through `DeviceManager`. Environmental measurements are provided by the BME688.

The Tower Pico is used automatically when an IR transmitter definition contains
`controller=tower-pico`; it does not add a separate top-level command.

## Logical Devices

```bash
tower device list
tower device show <device-id>
tower device create <device-id>
tower device set <device-id> <property> <value>
tower device alias add <device-id> <alias>
tower device alias remove <device-id> <alias>
tower device delete <device-id>
```

These commands manage the logical device records stored by Tower.

## Logical Device Commands

```bash
tower command list <device-id>
tower command show <device-id> <command-id>
tower command create <device-id> <command-id>
tower command set <device-id> <command-id> <property> <value>
tower command delete <device-id> <command-id>
```

These commands manage the logical commands attached to a device record.

```bash
tower execute <device-id> <command-id>
```

Resolves a logical device command and displays its configured transport, transport device, transport command, transmitter and enabled state.

The current implementation validates and resolves the command but does not yet transmit it.

## Infrared

```bash
tower learn <device-name> <command-name>
```

Captures an IR code through the userspace receiver and saves it.

```bash
tower learn-kernel
```

Interactively enables an IR protocol and waits for a decoded kernel input event.

```bash
tower replay <device-name> <command-name> <transmitter-name>
```

Loads a saved IR code and sends it through the selected IR transmitter.

Known IR replay command:

```bash
tower replay Denon VolumeUp Tower-IR-TX-001
```

## Radio Frequency

```bash
tower send <device-name> <on|off>
```

Loads a stored RF power-device definition and transmits its ON or OFF signal.

### Latest database activation commands

#### Old KAKU

Zoutlamp (`Tower-RF-Power-M1-001`):

```bash
tower send Tower-RF-Power-M1-001 on
tower send Tower-RF-Power-M1-001 off
```

Kat PC Monitor (`Tower-RF-Power-M1-002`):

```bash
tower send Tower-RF-Power-M1-002 on
tower send Tower-RF-Power-M1-002 off
```

#### Modern KAKU

Hoofd Buro Lamp Links (`Tower-RF-Power-M2-001`):

```bash
tower send Tower-RF-Power-M2-001 on
tower send Tower-RF-Power-M2-001 off
```

Hoofd Buro Lamp Rechts (`Tower-RF-Power-M2-002`):

```bash
tower send Tower-RF-Power-M2-002 on
tower send Tower-RF-Power-M2-002 off
```

Logitech Z5500 (`Tower-RF-Power-M2-003`):

```bash
tower send Tower-RF-Power-M2-003 on
tower send Tower-RF-Power-M2-003 off
```

DIY Buro Lamp (`Tower-RF-Power-M2-004`):

```bash
tower send Tower-RF-Power-M2-004 on
tower send Tower-RF-Power-M2-004 off
```

```bash
tower receive
```

Runs the current RF receiver diagnostic loop on GPIO4 and reports pulse timing together with ADS1115 AIN0 RSSI voltage.

Press `Ctrl+C` to stop it.

```bash
tower monitor
```

Runs the current RF edge-rate diagnostic on GPIO4 and reports the number of edges per second.

Press `Ctrl+C` to stop it.

The RF receive and monitor commands are still development diagnostics rather than finished RF capture commands.

## General and Development Diagnostics

```bash
tower version
```

Displays the Tower version.

```bash
tower config
```

Runs the current GPIO24 output test.

This is a development diagnostic, not a general configuration editor.
