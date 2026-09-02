## 2026-09-02 - PC thermal monitoring and Dell fan control

### Purpose and scope

The Windows application contains a dedicated PC tab for monitoring local
Windows hardware and controlling the main cooling bank on supported Dell
Precision systems.

This is a Windows-side extension. The Raspberry Pi Tower service is not involved
in collecting PC hardware data or writing Dell BIOS fan settings.

The feature was developed and tested on:

- Dell Precision 7820 Tower.
- Windows 11 25H2.
- Windows PowerShell 5.1.
- Dell Command | Monitor.
- NVIDIA RTX 2080 SUPER.
- Dell PERC H330.

The PC page deliberately remains clean. It displays useful live hardware values,
source status and the main cooling control. It does not add calculated
“highest temperature”, “highest fan”, dashboard summary or similar fields.

### Windows files

The feature is split across two PowerShell files:

- `windows/Tower-Control.ps1`
  - Owns the WinForms interface.
  - Creates and updates the PC tab.
  - Starts the PC monitor helper during application startup.
  - Reads completed snapshots without querying hardware on the UI thread.
  - Sends cooling commands to the helper.
  - Stops the helper when Tower Control exits.

- `windows/Tower-PC-Monitor.ps1`
  - Runs as an isolated background PowerShell process.
  - Queries Dell, NVIDIA, Windows Storage and PERC independently.
  - Serializes Dell sensor, Dell BIOS and Dell cooling operations.
  - Writes atomic JSON snapshots for the interface.
  - Performs cooling writes and verifies the Dell readback.
  - Restores Dell automatic fan control when required by the fail-safe.

Keeping slow vendor queries outside the WinForms process prevents the sidebar,
tray menu, EXIT button and animation from freezing.

### Startup and preload sequence

The PC monitor helper starts when Tower Control starts, not when the PC tab is
first opened.

The intended sequence is:

1. Tower Control starts the isolated helper.
2. The helper starts each available hardware collector.
3. Completed readings are written to an atomic JSON snapshot.
4. Tower Control checks the snapshot every 500 ms.
5. The PC tab updates from the latest completed snapshot.
6. Opening the PC tab normally shows already-loaded information.

Selecting the PC tab must not trigger a new synchronous hardware scan.

### Inter-process files

The UI and helper communicate through per-Tower-process files under:

`%APPDATA%\Tower`

The snapshot name contains the Tower Control process ID:

`pc-thermal-<TowerPID>.json`

Cooling-command and stop files use the same per-process ownership model. This
prevents two Tower Control instances from consuming or overwriting each
other's state.

Snapshots are replaced atomically. The interface should therefore see either
the previous complete snapshot or the next complete snapshot, never a
partially written JSON document.

### Independent hardware sources

Each source runs independently. A missing or failed optional source must not
stop values from the other sources.

#### Dell Command | Monitor: temperatures and fan RPM

Dell Command | Monitor exposes supported Dell hardware through the CIM
namespace:

`root/DCIM/SYSMAN`

The helper reads:

`DCIM_NumericSensor`

Relevant sensor types are:

- Sensor type 2: temperatures.
- Sensor type 5: fan RPM.

On the tested Precision 7820 this supplies:

- CPU0 and CPU1 temperatures.
- Memory temperature.
- CPU voltage-regulator temperature.
- Front and PCIe ambient temperatures.
- CPU0 and CPU1 fan RPM.
- SYS0, SYS1 and SYS2 fan RPM.
- REAR0 and REAR1 fan RPM.

A normal Dell sensor query took approximately eight seconds on the tested
machine. The collector waits 15 seconds after a completed read, making the
usual effective update interval approximately 20 to 25 seconds.

A previously overloaded Dell provider took 9 minutes and 39 seconds to return
one direct CIM query. To prevent that condition recurring:

- Dell queries are not stacked.
- A new Dell read is not started while the previous read is active.
- The helper applies a 30-second timeout.
- Failure retains the last good displayed values.
- The interface reports the Dell source state without blocking.
- The provider is allowed idle time between completed queries.

CPU temperatures therefore do not update instantly when fan speed changes.
Even though fan RPM rises quickly, the next visible CPU reading can be roughly
20 to 25 seconds later.

WMIC is not required. Windows 11 may offer WMIC as an optional feature, but
Tower Control uses PowerShell CIM commands such as `Get-CimInstance`.

#### Dell Command | Monitor: BIOS cooling control

The helper discovers Dell BIOS capabilities through Dell Command | Monitor.

The tested Precision 7820 exposes the writable attribute:

`Fan Speed Auto Level on CPU Memory Zone`

The Main Cooling Bank slider writes this Dell level from 0 through 100.

Important interpretation:

- The value is a Dell automatic fan-floor level.
- It is not a direct PWM percentage.
- Level 0 means Dell automatic control/baseline.
- The Dell Auto button writes level 0.
- BIOS Thermal/Climate control must remain set to Auto.
- A normal write and verified readback takes approximately 10 to 15 seconds.

The following fan bank responded during live testing:

- CPU0
- CPU1
- SYS1
- SYS2
- REAR0
- REAR1

SYS0 remained under Dell automatic control and is shown separately.

The overlapping Dell `PSU Zone` capability affects the same six controllable
fans. It is deliberately not exposed or written separately because doing so
would provide misleading duplicate controls.

Successful live tests:

- Level 20 increased the affected fan RPM.
- Level 80 produced a much stronger increase.
- Dell Auto restored the automatic baseline at level 0.
- Dell readback confirmed the applied value.

Dell BIOS capability discovery is cached and refreshed approximately every
600 seconds. Cooling writes, Dell sensor reads and BIOS discovery are
serialized so the Dell provider is not queried concurrently.

#### NVIDIA

The NVIDIA collector calls the `nvidia-smi` tool installed with the NVIDIA
display driver.

It supplies supported GPU values such as:

- Temperature.
- Fan percentage.
- Utilization/load.
- Power consumption.
- Health/availability state.

The NVIDIA collector updates approximately every two seconds. If NVIDIA
hardware or `nvidia-smi` is absent, only the NVIDIA source becomes unavailable.

#### Windows Storage

The storage collector uses the built-in Windows PowerShell Storage module:

- `Get-PhysicalDisk`
- `Get-StorageReliabilityCounter`

It supplies available physical-disk temperature and health information.

The storage collector updates approximately every eight seconds. Whether a
temperature is available depends on the storage controller, driver and disk.
A missing temperature is not automatically a disk fault.

Identityless storage entries are ignored. Transient Loading, Unknown or `--`
values do not overwrite a valid previously displayed temperature or health
value.

#### Dell PERC

The PERC collector uses `perccli64.exe`. The tested installation path is:

`C:\Program Files\Dell\Command Monitor\perccli64.exe`

It supplies the PERC controller temperature/status and supported physical-drive
slot health and temperatures.

The PERC collector updates approximately every 12 seconds. When `perccli64.exe`
is absent, the PERC source is unavailable without affecting the other
collectors.

### Source and UI refresh summary

- UI snapshot check: 500 ms.
- NVIDIA: approximately 2 seconds.
- Windows Storage: approximately 8 seconds.
- PERC: approximately 12 seconds.
- Dell sensors: 15 seconds after completion; approximately 20–25 seconds total
  on the tested PC.
- Dell BIOS capability refresh: approximately 600 seconds.
- Dell cooling write/readback: approximately 10–15 seconds.

These are independent schedules. The 600-second BIOS interval does not apply to
CPU temperature or fan RPM readings.

### Stable table update rules

The hardware table uses persistent rows keyed to the hardware component.

During refresh:

- Existing rows are not cleared and rebuilt.
- Rows are not removed and reinserted.
- The entire list is not wrapped in repeated whole-control redraw cycles.
- Only cells whose useful value actually changed receive new text.
- Last-known-good values survive transient Loading, Unknown or `--` results.
- Double buffering reduces native WinForms drawing artifacts.

These rules fixed the visible table flicker and brief orange Unknown states.
They also allow the page to remain fully populated while collectors perform
their next read.

### Error isolation and application responsiveness

Every hardware provider has its own source status. One source can be Loading,
Unavailable or Error while completed readings from other sources continue to
update.

Timer and asynchronous completion handlers catch their own failures. A
background provider error must not escape into the WinForms message loop or
open a modal unhandled `.NET Framework` exception dialog.

Hardware access never runs synchronously inside:

- The PC-tab selection event.
- The edge-trigger/sidebar animation timer.
- The tray menu.
- The EXIT button.

This keeps window sliding, hiding and exiting responsive even when Dell CIM is
slow or unavailable.

### Cooling fail-safe

The helper owns every non-zero Dell cooling level that it writes.

If Tower Control closes, disappears or requests helper shutdown while a
non-zero manual level is owned, the helper attempts to restore Dell automatic
control by writing level 0.

The application must not silently leave a manual fan floor active after exit.

### Required and optional software

Tower does not redistribute vendor utilities. The correct packages should be
installed separately for the target hardware and operating system.

Required for the Windows interface:

- Windows PowerShell 5.1.
- Microsoft .NET Framework/WinForms supplied with Windows.

Required for Dell CPU temperatures, Dell fan RPM and Dell fan control:

- Dell Command | Monitor.
- A Dell system whose installed provider exposes the required sensors and a
  writable cooling capability.
- Elevated execution for BIOS cooling writes.

Optional:

- NVIDIA display driver including `nvidia-smi` for NVIDIA GPU telemetry.
- Windows Storage module for physical-disk telemetry; normally built into
  Windows.
- `perccli64.exe` for Dell PERC information.

Dell Command | Monitor is hardware-specific. Installing it does not guarantee
that every Dell model exposes the same classes, attributes or writable fan
controls.

### Portability rules

There is no single universal Windows fan-control API that safely supports every
motherboard. Tower must not include generic motherboard drivers or assume that
the Precision 7820 Dell attribute exists elsewhere.

For another PC:

- Detect every provider independently.
- Show values from providers that are available.
- Omit or mark unavailable only the missing source.
- Keep Dell fan controls disabled until the exact writable capability has been
  discovered.
- Permit monitor-only operation when Dell sensors exist but fan control does
  not.
- Never guess BIOS attribute names or fan mappings.
- Require model-specific testing before enabling writes.

The entire PC tab does not need to be disabled merely because one optional
provider is absent. GPU or storage monitoring can remain useful without Dell
fan control.

### Display numbering

The Settings page identifies displays using Windows `Screen.DeviceName` values,
such as `DISPLAY1`, `DISPLAY2` and `DISPLAY3`, rather than the temporary order
returned by screen enumeration.

The selected device name is persisted. This keeps Tower Control attached to the
same Windows-numbered monitor when another display is enabled or disabled.

### Deferred automatic climate control

Automatic Tower-managed fan curves are not implemented in v0.11.03.

A future climate-control layer may use the stable collectors and verified Dell
write path, but it must include:

- Conservative temperature thresholds.
- Hysteresis to prevent fan hunting.
- Minimum hold times between changes.
- Stale-data detection.
- Emergency high-temperature behavior.
- Automatic fallback to Dell level 0.
- Clear ownership and shutdown recovery.
- Explicit per-model capability validation.

Until those safeguards are designed and tested, Dell BIOS Auto remains the
normal operating mode and manual levels remain temporary user-requested
overrides.