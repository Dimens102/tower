# Tower Roadmap

> Last updated: 2026-07-01

---

# Vision

Tower is a modular home automation platform.

Tower should become the central system that controls, monitors and automates devices using multiple hardware interfaces while remaining hardware independent through clean driver abstractions.

The project is built around small reusable modules instead of one large application.

---

# Foundation

Status: 80%

[x] Git repository
[x] CMake build system
[x] Versioning
[x] Command parser
[x] GPIO abstraction
[x] GPIO input
[x] GPIO edge events
[ ] GPIO output
[ ] Driver Manager
[ ] Logging system
[ ] Configuration system

---

# Drivers

Status: 15%

GPIO
------
[x] Input
[x] Edge detection
[ ] Output
[ ] PWM

SPI
-----
[ ] Generic SPI driver

I²C
-----
[ ] Generic I²C driver

UART
------
[ ] Generic UART driver

Bluetooth
-----------
[ ] Bluetooth manager
[ ] HID keyboard
[ ] HID media remote

---

# Radio

Status: 5%

433 MHz
---------
[x] Basic receiver
[ ] Pulse capture
[ ] Pulse timing
[ ] Noise filtering
[ ] Packet detection
[ ] Protocol detection

868 MHz
---------
[ ] CC1101 driver

IR
----
[ ] Receiver
[ ] Transmitter
[ ] Learning
[ ] Database

---

# Protocols

Status: 0%

RF

[ ] PT2262
[ ] EV1527
[ ] HT6P20
[ ] Raw Pulse

IR

[ ] NEC
[ ] RC5
[ ] RC6
[ ] Sony
[ ] Panasonic

---

# Device Library

Status: 0%

Current planned devices

[ ] Denon AVR
[ ] Logitech Z5500
[ ] Eurom Arico
[ ] KPN TV
[ ] Dell 1610HD

Future

[ ] Weather stations
[ ] PIR sensors
[ ] Temperature sensors
[ ] Relays
[ ] Light switches

---

# Automation

Status: 0%

[ ] Scheduler

[ ] Event system

[ ] Rules engine

[ ] Scenes

[ ] Notifications

---

# Interfaces

Status: 5%

[x] Command Line

[ ] REST API

[ ] Web Interface

[ ] Mobile Interface

---

# Long Term Vision

Tower should eventually support:

- GPIO
- SPI
- I²C
- UART
- IR
- RF
- Bluetooth
- Camera
- Audio
- Ethernet
- WiFi

Every hardware interface should appear as a driver.

Everything above the driver layer should be completely hardware independent.

---

# Current Milestone

Build the hardware driver layer.

Current focus:

GPIO
↓

IR

↓

RF

↓

I²C

↓

Automation
