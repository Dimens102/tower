# Automation Engine

The Tower daemon should own automation execution. Web, phone, and desktop interfaces should only edit or invoke automation objects.

## Responsibilities

The automation engine should manage:

- schedules
- triggers
- conditions
- actions
- delays
- retries
- logging
- enabled/disabled state
- execution history

## Action model

An action should target a logical device command:

```text
LivingRoomReceiver.Power
```

The engine asks the device database to resolve that command. The database selects the transport and driver.

The automation must not execute data files directly:

```text
send data/ir/Denon/Power.ir
```

## Suggested automation object

```text
id
name
description
enabled
trigger
conditions
actions
created_at
updated_at
```

## Trigger examples

- specific time
- recurring schedule
- sunrise or sunset
- incoming API request
- RF or IR event
- GPIO state
- device state change
- future sensor event

## Condition examples

- day of week
- time range
- device state
- presence
- sensor threshold
- another automation state

## Action examples

- execute a logical device command
- wait
- execute a command again
- update state
- call an internal API
- run another automation

## Interface boundary

The web interface and phone app should:

- create and edit devices
- create and edit automations
- show state and history
- request command execution

They should not implement scheduling, conditions, protocol encoding, or hardware access.

## Local display boundary

The automation engine must not control the LCD or GPIO26 directly. It may expose
automation status and execution events for the display layer to show, while
`TowerService` and the display components remain responsible for presentation
and backlight behavior.
