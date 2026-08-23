# Tower Project Goals

Tower is a Raspberry Pi-based home automation controller for transmitting,
receiving, scheduling, and remotely activating IR and RF commands.

This document records the intended end-state of the project and the priority
in which major capabilities should be implemented.

## Priority order

The numbered goals below are ordered by importance.

Development should first establish the shared foundations required by all
goals, but user-facing functionality should then be implemented in this order.

## 1. IR and RF learning and playback

Tower must be able to:

- Receive and record IR signals.
- Receive and record RF signals.
- Identify decoded protocol data when reliable.
- Retain raw signal data when decoding is unavailable or unsuitable.
- Store learned signals as commands belonging to logical devices.
- Replay stored IR commands.
- Replay stored RF commands.
- Select the correct physical transmitter or output.
- Validate learned commands through test playback.
- Replace or relearn a command without breaking schedules or remote controls.

Examples:

```text
LivingRoomReceiver.Power
KPNReceiver.Button1
Projector.PowerOn
BedroomLight.On
```

Logical device and command names must not depend on physical filenames,
GPIO numbers, transmitter hardware, or protocol implementation.

## 2. Rules, schedules, and action sequences

Tower must execute actions automatically based on time, sensor values, or
other conditions.

Examples:

```text
If temperature is at least 24 C:
    Send AirConditioner.PowerOn
```

```text
At 07:30:
    Send KPNReceiver.PowerOn
    Send KPNReceiver.Button1
    Send LivingRoomReceiver.PowerOn
    Send DellProjector.PowerOn
```

The automation system must eventually support:

- Time-based schedules.
- Sensor-value conditions.
- Multiple conditions.
- Delays between actions.
- Ordered action sequences.
- Enable and disable controls.
- Manual execution.
- Logging of every execution and result.
- Protection against repeatedly triggering the same rule.
- Future expansion to additional condition and action types.

The first automation-engine implementation may execute logical commands
without a scheduler. Scheduling and sensor-triggered evaluation can then be
added on top of that engine.

## 3. Control from the main PC

A small desktop control program must be able to command Tower over the local
network.

The PC interface should:

- Display selected devices and commands.
- Send logical commands rather than raw protocol data.
- Show whether Tower accepted and executed a command.
- Allow devices and buttons to be configured without changing program code.
- Be replaceable later without changing Tower's internal database.

The first client may be created using a simple Windows-compatible technology.
The network protocol must not depend on VBScript or any specific client
implementation.

Tower should expose a stable authenticated API that can also be used by future
desktop applications.


## Desktop control application v2

The Windows control application should become Tower's primary desktop user
interface while remaining a replaceable client of the Tower service.

Required behaviour:

- Resolve the recurring HTTP 400/stale-service problem so normal use does not
  require manually restarting Tower services.
- Operate as an auto-hiding panel attached to the right edge of a selected
  monitor.
- Support multi-monitor systems and remember the selected monitor.
- Open to approximately one third of the selected monitor when the pointer
  reaches the right screen edge.
- Allow configurable panel width, auto-hide delay, appearance, and related UI
  preferences.
- Show artwork of the original physical remote alongside the Tower controls.
- Support transparent remote artwork so the UI background can be customized.
- Present commands in functional groups and approximately reproduce useful
  physical relationships from the original remote.
- Give command buttons a visible pressed/held state.
- Support hold/repeat semantics for commands where repeated transmission is
  meaningful.
- Show TX-001 through TX-006 for IR devices and allow one or more transmitters
  to be selected for a remote/device.
- Clearly show which transmitter buttons are active.
- Allow custom actions such as executing Volume Up ten times.
- Show small icons or thumbnails beside RF controls where useful for visual
  recognition.
- Provide a Programs page for creating and managing schedules and command
  sequences.
- Store and execute all programs on Tower itself so automations continue when
  the Windows PC is shut down.
- Prepare program definitions for future voice-intent mappings.
- Allow a device/remote profile to be deleted from the Windows application,
  with the actual deletion performed through Tower's API.

The Windows client must not directly manipulate IR/RF files or implement a
scheduler. It should discover logical devices, commands, transmitter routing,
and automation objects through Tower's network API.


## 4. Voice control

Tower must support local voice commands through a connected microphone.

The voice-control system should:

- Recognize an explicit wake word or activation phrase.
- Avoid reacting to television, movies, music, or ordinary conversation.
- Map spoken phrases to logical Tower commands.
- Request confirmation for dangerous or ambiguous actions when appropriate.
- Allow aliases and natural phrases for devices and commands.
- Continue to function locally when practical.
- Keep speech recognition separate from the command-execution engine.

Example:

```text
"Tower, turn on the projector"
```

maps to:

```text
DellProjector.PowerOn
```

Voice recognition is an input method. It must use the same command API as the
PC and phone clients.

## 5. Remote phone control

Tower must be controllable from a phone, including from outside the home
network.

The phone interface should eventually support:

- A configurable selection of devices and commands.
- Manual command execution.
- Command status and recent history.
- Viewing sensor readings.
- Enabling and disabling schedules.
- Creating or editing schedules, if this can be done safely and clearly.
- Secure authentication.
- Encrypted communication.
- Restricted external exposure.

Tower may listen on a configured network port, but direct internet exposure
must be designed securely. Port forwarding alone must not be treated as
sufficient security.

The phone application must use the same stable API as other clients.

## 6. Local display

The display should normally show environmental
and system information such as:

- Time.
- Temperature.
- Humidity.
- Air pressure.
- Tower status.

The display should also support temporary user-requested
information through voice commands.

Examples include:

- Current temperature.
- Current humidity.
- Air quality.
- Running programs or services.
- Current automation status.
- Network status.

After a configurable timeout the display should automatically
return to its normal information screen.

When Tower receives, learns, or transmits a command, the display should
temporarily show relevant event information, such as:

- Device.
- Command.
- Transport.
- Protocol.
- Transmitter.
- Success or failure.

After a configurable delay, the display should return to its normal
information screen.

The display is an output interface and should consume Tower events rather
than being directly coupled to IR or RF code.

### Current implementation

Tower currently uses an HD44780-compatible 20x4 LCD connected through
an I2C backpack at address `0x27`.

The normal display shows:

- Room temperature.
- Aquarium temperature from remote source `ID1`.
- Room humidity.
- Air pressure.

The LCD backlight is controlled by a push button connected between
GPIO26 and ground. GPIO26 uses an internal pull-up resistor.

Button behaviour:

- A single press enables the backlight for 30 seconds.
- A second single press restarts the 30-second timeout.
- A double press within one second locks the backlight on.
- Another double press switches the backlight off.
- A single press while locked on returns it to timed operation.

Both rising and falling GPIO edges are used to debounce the physical
button and ensure that one physical press is counted only once.

# Required shared architecture

The six goals require the following shared layers.

## Logical device database

The device database is the source of truth for:

- Stable device IDs.
- Friendly names.
- Device types.
- Manufacturer and model.
- Location.
- Enabled state.
- Commands and capabilities.
- Voice aliases.
- UI visibility.
- Transport mappings.

A logical command should resolve to a transport-specific implementation.

Example:

```text
LivingRoomReceiver.PowerOn
    -> transport: IR
    -> stored signal: denon_x2800_power_on
    -> transmitter: living_room_ir
```

## Transport backends

Transport-specific storage and transmission remain separate.

Initial transports:

- IR.
- RF.

Possible future transports:

- GPIO.
- HTTP.
- MQTT.
- Serial.
- Zigbee.

Existing IR and RF database code may be retained or modified as transport
backends underneath the logical device database.

## Sensor registry

Sensors require stable logical identities similar to controllable devices.

Examples:

```text
LivingRoom.Temperature
LivingRoom.Humidity
LivingRoom.Pressure
```

Sensor definitions should contain:

- Stable sensor ID.
- Type.
- Unit.
- Location.
- Hardware or source.

Hardware or source may be either local or remote.

Examples include:

- Local BME688.
- Remote Raspberry Pi temperature service.
- HTTP weather provider.
- Current value.
- Last update time.
- Validity or availability state.

Sensor history may later use separate storage.

## Automation database

Rules and schedules should be stored separately from device transport data.

An automation definition may contain:

- Stable automation ID.
- Friendly name.
- Enabled state.
- Trigger.
- Conditions.
- Ordered actions.
- Delays.
- Cooldown or retrigger policy.
- Last execution result.

Automations must reference stable logical device, command, and sensor IDs.

## Command execution engine

All input methods must call one shared execution path:

```text
Scheduler
PC client
Voice control
Phone application
Local command line
    -> Tower command API
    -> Device lookup
    -> Transport execution
    -> Event log
```

This prevents each interface from implementing its own IR or RF logic.

## Service and API

Tower will eventually run as a persistent service.

The service should provide:

- Logical command execution.
- Sensor readings.
- Device and command discovery.
- Automation management.
- Event and status information.
- Authentication and authorization.
- A versioned network API.

The command-line program may remain available as an administration and
diagnostic client.

## Event system and logging

Tower should emit structured events for:

- Commands requested.
- Commands executed.
- Commands failed.
- Signals received.
- Signals learned.
- Sensor updates.
- Rules triggered.
- Client connections.
- Configuration changes.

The display, logs, remote clients, and diagnostics can consume these events
without being directly connected to transport code.

# Development sequence

The intended implementation order is:

1. Establish the logical device and command data model.
2. Establish the shared execution engine (Scheduler, TimerManager and callbacks).
3. Complete reliable IR and RF learning and playback.
4. Implement logical command lookup and shared command execution.
5. Add sensor definitions and readings.
6. Add schedules and condition-based rules.
7. Add the local network API and PC client.
8. Add voice control.
9. Add secure remote phone control.
10. Add the local status display.

Shared foundations may be implemented before their corresponding user-facing
goal when doing so avoids later redesign.

# Design principles

- Existing working code is evaluated and reused where appropriate.
- Existing code may be refactored or replaced when required by the final design.
- Logical identities must remain stable when hardware changes.
- Interfaces must not access IR or RF storage directly.
- Transport-specific details must remain isolated from generic device metadata.
- Security must be designed before exposing Tower outside the local network.
- Every significant action should be observable through status and logging.
- Tower should remain functional when optional interfaces are unavailable.