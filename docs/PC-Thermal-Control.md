# PC Thermal / Fan Control

> Status: Phase 3 manual Main Cooling Bank control and resilient Dell collectors implemented; adaptive climate engine not yet enabled
> Target validated hardware: Dell Precision 7820, Windows 11
> Dell interface: Dell Command | Monitor, `root\DCIM\SYSMAN`

## Purpose

The Tower Control Windows application has a local `PC` tab for monitoring and,
later, managing cooling behavior on the workstation running the client.

This feature is deliberately separate from Raspberry Pi Tower hardware.
Telemetry and BIOS capability discovery are read locally from Dell Command |
Monitor through `System.Management`.

The long-term goal is controlled workstation cooling with user-defined profiles,
but the software must first establish exactly how this Precision 7820 firmware
responds to Dell's exposed settings.

## Confirmed Precision 7820 telemetry

`DCIM_NumericSensor` exposes temperatures with `SensorType=2` and fan RPM with
`SensorType=5`.

Observed temperatures:

| Dell sensor | UI label | Example reading |
|---|---|---:|
| `CPU0 PECI` | CPU0 | 60 C |
| `CPU1 PECI` | CPU1 | 45 C |
| `MEM_TOP PECI` | Memory | 34 C |
| `CPU1 VR` | CPU VR | 39 C |
| `FRONT PANEL` | Front Ambient | 25 C |
| `PCIE_AMB` | PCIe Ambient | 26 C |

Observed fan telemetry:

| Device ID | Dell sensor | Example |
|---|---|---:|
| `Root/MainSystemChassis/FanObj:0` | CPU0 FAN | 1806 RPM |
| `Root/MainSystemChassis/FanObj:1` | CPU1 FAN | 1794 RPM |
| `Root/MainSystemChassis/FanObj:2` | SYS0 FAN | 898 RPM |
| `Root/MainSystemChassis/FanObj:3` | SYS1 FAN | 1750 RPM |
| `Root/MainSystemChassis/FanObj:4` | SYS2 FAN | 2078 RPM |
| `Root/MainSystemChassis/FanObj:5` | REAR0 FAN | 1863 RPM |
| `Root/MainSystemChassis/FanObj:6` | REAR1 FAN | 1929 RPM |
| `Root/MainSystemChassis/FanObj:7` | HDD FAN | no current reading |
| `Root/MainSystemChassis/FanObj:8` | PSU FAN | no current reading |

Tower Control polls this telemetry every second **only while the PC tab is
selected**.

It uses one persistent:

```text
System.Management.ManagementScope
\\.\root\DCIM\SYSMAN
```

It does not start a new PowerShell process for polling.

## Confirmed Precision 7820 capability discovery

The real workstation was queried before write support was designed.

Results:

- `DCIM_ThermalInformation`: no useful exposed instance/value for this machine.
- `DCIM_BIOSInteger`: no matching useful fan/thermal control.
- `DCIM_BIOSEnumeration`: useful writable cooling controls are exposed here.

Confirmed attributes:

| Attribute | Range / values | Current observed | Writable |
|---|---|---:|---|
| Fan Speed Auto Level on CPU Zone | 0-100 | 0 | yes |
| Fan Speed Auto Level on CPU Memory Zone | 0-100 | 0 | yes |
| Fan Speed Auto Level on PCIe Zone | 0-100 | 0 | yes |
| Fan Speed Auto Level on Upper PCIe Zone | 0-100 | 0 | yes |
| Fan Speed Auto Level on PSU Zone | 0-100 | 0 | yes |
| Fan Speed Auto Level on Flex Bay Zone | 0-100 | 0 | yes |
| HDD0 Fan Enable | 1=Enable, 2=Disable | 2 | yes |

These values are **Dell automatic cooling levels**, not proven raw PWM
percentages.

Interpretation:

```text
0   = Dell normal/automatic baseline
50  != proven 50% PWM
100 != proven exact 100% PWM
```

Precision 7820 testing proved that these values become active only while the BIOS Thermal/Climate mode is set to **Auto**. Under Auto, `CPU Memory Zone` values apply live and ramp the mapped fan bank. Tower therefore exposes one validated **Main Cooling Bank** control rather than six misleading independent sliders.

`DCIM_FAN` reports `VariableSpeed=True`, but its direct control properties were
blank during discovery. `DCIM_FAN` is not treated as a proven write API.

## PC tab implementation

### Summary

The tab displays:

- Dell Command | Monitor connection state
- independent Dell/GPU/storage/PERC/BIOS source state
- the live hardware temperature/fan table
- the validated Main Cooling Bank control and its affected live RPM values

Per-row health uses Dell sensor metadata where available:

- `HealthState`
- upper/lower non-critical thresholds
- upper/lower critical thresholds

No arbitrary CPU temperature threshold is required for the current monitor.

The BIOS Thermal/Climate mode is not exposed by Dell Command | Monitor on this
Precision 7820. Tower therefore does not display a guessed or static thermal
profile value.

## v81 - serialized Dell access and supervised recovery

v78 allowed `DCIM_NumericSensor`, `DCIM_BIOSEnumeration`, and cooling writes to
enter Dell Command | Monitor concurrently. On the validated machine this could
leave Dell sensors and BIOS discovery running forever while the other hardware
collectors continued normally.

v81 serializes every Dell provider operation while leaving GPU, storage and
PERC independent. Dell's own CIM operation timeout is left at its provider
default because short `OperationTimeoutSec` values caused valid Precision 7820
queries to fail with `Timed out`. Separate 30-second sensor and 45-second BIOS
wall-clock watchdogs supervise the helper instead.

A persistent ownership marker records when Tower may have applied a non-zero
Main Cooling Bank floor. A replacement helper restores Dell Auto (0) before
resuming normal Dell polling, so timeout recovery does not forget cooling
ownership.

Snapshot, stop and cooling-command files are unique to each Tower Control PID.
Starting a new UI instance can therefore no longer remove the stop request or
snapshot belonging to an older helper that is still shutting down.

All persistent WinForms timers use a non-modal exception boundary. A timer
failure is throttled and written to `tower-control.log`; it cannot open the .NET
unhandled-exception dialog and block the Tower controls.

## v82 - calm Dell polling and non-stacking timeout recovery

Live testing showed that one healthy `DCIM_NumericSensor` enumeration takes
about eight seconds on this Precision 7820. Keeping that query almost
continuously active eventually wedged the Dell provider: the same direct query
then took 9 minutes 39 seconds and returned no instances. A clean restart
restored all 15 sensor instances immediately.

Dell sensor sampling therefore leaves 15 seconds of provider idle time after
each completed query. BIOS capability discovery refreshes every 10 minutes
instead of every 30 seconds; a cooling write still requests an immediate BIOS
readback.

Crossing a Dell watchdog threshold now publishes one `Timeout` state but does
not kill and immediately restart the helper. Ending the client process cannot
guarantee cancellation of work already executing inside WMI Provider Host, and
an immediate replacement could stack another request onto the same stuck
provider. Tower waits for the existing call to finish before submitting another
Dell operation. GPU, storage and PERC collectors continue independently.

After successful BIOS discovery, the Main Cooling Bank status explicitly moves
from `Reading` to `Ready`. `Current Dell level` is the value read back from the
BIOS provider; `Target` is the unapplied slider selection.

### Temperatures

A persistent list shows all `SensorType=2` readings.

The known Precision 7820 names receive friendly labels, but unknown sensors are
still displayed rather than discarded.

### Fan RPM

A persistent list shows all `SensorType=5` readings and their DeviceID.

Missing HDD/PSU readings remain `--`/`No reading`.

### Main Cooling Bank

The Precision 7820 zone controls were tested at level 100 while monitoring all
reported fan RPMs. The result is not six independent fan channels.

Validated actuator:

```text
Fan Speed Auto Level on CPU Memory Zone
```

Mapped fan response:

| Fan | Controlled by Main Cooling Bank |
|---|---|
| CPU0 FAN | yes |
| CPU1 FAN | yes |
| SYS0 FAN | no - Dell automatic only |
| SYS1 FAN | yes |
| SYS2 FAN | yes |
| REAR0 FAN | yes |
| REAR1 FAN | yes |

`Fan Speed Auto Level on PSU Zone` also raised the same six-fan bank during
testing, so Tower intentionally leaves PSU Zone at 0 and uses only CPU/Memory
Zone as the single actuator. CPU Zone, PCIe Zone, Upper PCIe Zone and Flex Bay
Zone produced no meaningful RPM response in the validated configuration.

The manual UI shows:

- current Dell level/readback;
- a 0-100 target slider;
- explicit **Apply** button;
- **Dell Auto** button which writes 0;
- live RPM for all six affected fans;
- SYS0 separately as Dell automatic only.

Moving the slider does not write anything. A BIOS write occurs only when the
user presses **Apply** or **Dell Auto**.

The write is executed inside the isolated helper in its own runspace, so the
10-15 second Dell BIOS provider latency never blocks the Tower WinForms UI or
the independent telemetry collectors. The helper validates the exact attribute,
checks `IsReadOnly=False`, writes through `DCIM_BIOSService.SetBIOSAttributes`,
and verifies readback before reporting success.

Fail-safe behavior: if Tower has applied a non-zero cooling floor and the Tower
UI closes or its parent process disappears, the helper attempts to restore
CPU/Memory Zone to 0 before exiting. A non-zero Tower value therefore fails
toward extra cooling/noise rather than reduced Dell cooling.

## Development phases

### Phase 1 - implemented

- persistent local Dell WMI connection
- 1-second temperature polling
- 1-second fan RPM polling
- Dell threshold/health display
- no shell process per polling cycle

### Phase 2 - implemented read-only

- discover `DCIM_ThermalInformation`
- discover `DCIM_BIOSEnumeration`
- discover `DCIM_BIOSInteger`
- display current zone levels
- display read/write capability
- display HDD0 Fan Enable state

### Phase 3 - implemented manual control

- one validated writable actuator: CPU/Memory Zone;
- explicit 0-100 manual target with Apply;
- Dell Auto hand-back at level 0;
- write/readback verification;
- write work isolated from the UI and telemetry collectors;
- helper/parent-process fail-safe hand-back to 0 for Tower-owned non-zero levels.

### Phase 4 - implemented mapping

Empirical fan-zone mapping is complete for the useful Precision 7820 controls.
CPU/Memory Zone is the primary Main Cooling Bank actuator. PSU Zone overlaps the
same fan bank and is intentionally not used by Tower. SYS0 remains under Dell
automatic control.

### Phase 5 - next: adaptive climate engine

Add the user-defined climate controller only on top of the now-proven manual
actuator. Requirements remain:

- Dell automatic policy at level 0 is the fallback;
- temperature state with green/orange/red presentation;
- trend/rate-of-rise detection;
- hysteresis and prolonged-temperature dwell;
- gradual normal ramp-up;
- very slow ramp-down toward a configurable quiet baseline;
- fast escalation for red/emergency conditions;
- minimum dwell between BIOS writes;
- hand-back to Dell Auto if telemetry disappears or the helper fails.

The controller must never attempt to replace Dell hardware thermal protection.


## v84 - stable telemetry display

Live workstation testing verified the Main Cooling Bank at manual levels 20 and
80, including Dell readback and corresponding increases across CPU0, CPU1,
SYS1, SYS2, REAR0 and REAR1. Dell Auto successfully restored level 0, while
SYS0 remained under Dell automatic control as designed. A write/readback cycle
normally takes roughly 10-15 seconds on this Dell provider.

The PC hardware table now preserves its ListView rows and updates temperature,
RPM, load, power, limits and health text in place. Double buffering is enabled
for the table, and a full row rebuild is reserved for a real hardware topology
change. This removes the recurring clear/repaint flicker without changing the
page contents or adding summary fields.


## v85 - partial snapshot retention

An animated screen capture proved that the residual v84 flash came from whole
row groups being briefly removed between asynchronous collector updates. v85
keeps every established hardware row for the lifetime of the Tower process and
retains its last good text when another source publishes. Newly discovered rows
are inserted once; no recurring clear, removal or reordering occurs.


## v86 - stable cells and startup preload

The table-wide redraw suppression cycle has been removed so live telemetry
updates repaint only the cells that changed. Valid temperature, RPM and health
text survives a temporary missing/Loading/Unknown collector value, while the
Sources line continues to report collector state. Identityless storage entries
are discarded instead of appearing as an orange `-- / Unknown` row.

Tower starts the PC helper and consumes snapshots from startup regardless of
which tab is visible. This preloads Dell, GPU, storage, PERC and BIOS data before
the user opens the PC page whenever the collectors have had time to finish.


## v74 - isolated Dell CIM helper

The first in-process implementations proved too risky with the Dell provider on
this workstation. Dell CIM is therefore isolated from Tower Control itself.

Tower Control starts one hidden, persistent `Tower-PC-Monitor.ps1` process when
the PC tab is first used. That helper executes the exact `Get-CimInstance`
queries already validated on the Precision 7820 and writes an atomic snapshot
to `%APPDATA%\Tower\pc-thermal-<TowerPID>.json`. The per-process name prevents
a newly started UI from interfering while an older helper shuts down.

Tower Control only reads the JSON snapshot. If Dell Command | Monitor hangs,
throws, or terminates the helper, the main WinForms application remains alive.

This is still a single long-lived process, not a new PowerShell process per
sensor refresh.


## v75 - broad hardware discovery

The PC page now has two local sub-pages:

```text
Overview
Discovery
```

`Discovery` is intentionally a raw read-only inventory/telemetry table used to
determine what the workstation can actually expose before the final dashboard
layout is designed.

Collectors currently probe:

- Dell Command | Monitor `DCIM_NumericSensor`, including sensor types beyond
  the normal temperature/fan overview;
- Dell thermal/fan BIOS enumeration;
- NVIDIA `nvidia-smi` GPU temperature, intended fan percentage, utilization,
  power, VRAM usage, P-state, PCI bus and driver;
- Windows `Get-PhysicalDisk` + `Get-StorageReliabilityCounter` for temperature,
  maximum temperature, wear, power-on hours, error counters, health, media type
  and bus type;
- `perccli64.exe` in `C:\Program Files\Dell\Command Monitor` using controller
  and detailed physical-drive JSON output, flattened into raw discovery rows;
- Windows network adapter inventory;
- Windows sound-device inventory.

Discovery refresh is deliberately slower (approximately every 15 seconds) than
Dell CPU/fan telemetry.

### v75 telemetry corrections

The Precision 7820 testing proved that Dell Command | Monitor already returns
human-readable temperature values in `CurrentReading`. For example, a value of
`62` means approximately `62 C` even though the object also reports
`UnitModifier=-1`.

v75 therefore no longer applies `UnitModifier` to Dell temperature readings or
thresholds.

Dell fan sensors also expose numeric threshold fields around `245/255` while
their real RPM readings are around 900-2200 RPM. Those fields are not treated
as RPM warning/critical limits. Fan health currently uses Dell `HealthState`
rather than comparing RPM to those threshold numbers.


## v76 - independent collectors

The temporary Discovery page was replaced by a single combined hardware
thermal/fan view.

Dell sensors, NVIDIA, Windows storage reliability, PERC and Dell BIOS cooling
capabilities now execute independently in a five-runspace helper pool. The
helper writes an initial snapshot immediately and publishes again as each
source completes. Tower-Control.ps1 only reads the local JSON snapshot and
never performs the hardware management calls itself.

v76 itself had no BIOS writes. v78 adds the validated manual Main Cooling Bank write path described above.
