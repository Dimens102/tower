# Controller Design

## Status

**State:** Implemented (Phase 1)

The Controller runtime category has been introduced into the runtime architecture.

Current implementation:

- Controller derives from `ManagedDevice`.
- ADS1115 has been migrated from `Sensor` to `Controller`.
- `DeviceManager` manages controllers through the common `ManagedDevice` lifecycle.

Future controller implementations (such as the PCF8574) will build upon this foundation.

---

# Purpose

A Controller is a runtime-managed hardware device that primarily provides control over external hardware rather than producing measurements.

Controllers abstract hardware interfaces and expose capabilities to the rest of the system without requiring other components to know how the hardware is implemented.

Examples include GPIO expanders, PWM generators, relay boards, and ADCs.

---

# Goals

- Provide a common abstraction for controllable hardware.
- Support runtime lifecycle through `ManagedDevice`.
- Hide hardware-specific implementation details.
- Allow future hardware replacements with minimal application changes.
- Keep hardware initialization and diagnostics centralized.

---

# Non-Goals

Controllers are **not** responsible for:

- Application logic
- Device automation
- Scheduling
- RF/IR protocols
- Business logic

Controllers only expose hardware capabilities.

---

# Planned Class Hierarchy

```text
ManagedDevice
│
├── Sensor
├── Controller
└── RemoteSource
```

---

# Current Controllers

## ADS1115

**Status:** Implemented

Purpose:

- Four-channel analog-to-digital converter.
- Extends the Raspberry Pi with additional analog input channels.

Responsibilities:

- Read analog voltages.
- Publish channel measurements.
- Handle ADC configuration and conversion.
- Provide RSSI measurements for the RF receiver.

---

# Planned Controllers

## PCF8574

Purpose:

- Digital GPIO expansion.

Responsibilities:

- Provide additional digital input/output pins.
- Maintain output states.
- Read digital inputs.
- Replace Raspberry Pi GPIO usage where appropriate.

## ADS1115

Purpose:

- Analog-to-digital converter

Responsibilities:

- Read analog voltages
- Publish measurement channels
- Handle ADC configuration

---

## PCF8574

Purpose:

- Digital GPIO expansion

Responsibilities:

- Provide additional digital input/output pins
- Maintain output states
- Read digital inputs
- Replace Raspberry Pi GPIO usage where appropriate

---

# Future Controllers

Possible future implementations:

- PCA9685
- MCP23017
- Relay boards
- Motor controllers
- LED controllers
- DAC devices

---

# Lifecycle

Controllers participate in the standard runtime lifecycle.

```cpp
initialize()
update()
available()
name()
```

---

# Ownership

Controllers are owned by `DeviceManager`.

Application code should never create controller instances directly.

---

# Communication

Controllers expose hardware capabilities.

Higher-level runtime components consume those capabilities.

Example:

```text
IR Transmitter
        │
        ▼
PCF8574 Controller
        │
        ▼
I²C Bus
```

The transmitter should not know how the GPIO is implemented.

---

# Design Principles

- Single Responsibility Principle
- Hardware abstraction
- Runtime managed
- Easily testable
- Replaceable implementations
- Minimal public API
- Clear ownership

---

# Open Questions

## ADS1115

- Should channels be represented as individual objects?
- Should calibration be built into the driver?
- Should sampling be configurable?

---

## PCF8574

- Should pin objects exist?
- Should outputs be buffered?
- Should inputs support interrupt handling later?

---

# Future Work

After introducing `Controller`:

1. Move ADS1115 from `Sensor`.
2. Add PCF8574 support.
3. Migrate IR transmitters to PCF8574 outputs.
4. Free Raspberry Pi GPIO resources.
5. Evaluate additional controller types.