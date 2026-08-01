# IR Receiver Array

RF Tower uses six demodulating IR receivers so learning can compare the same
button press at several carrier frequencies.

| GPIO | Receiver | Nominal carrier | Position |
|---:|---|---:|---|
| 17 | TSOP38230 | 30 kHz | West |
| 18 | TSOP38233 | 33 kHz | West |
| 27 | TSOP34836 | 36 kHz | West |
| 22 | TSOP38238 | 38 kHz | South |
| 23 | TSOP38240 | 40 kHz | South |
| 25 | TSOP38256 | 56 kHz | South |

Linux does not guarantee stable `rcX` or `/dev/lircX` numbers across boots.
`IRReceiverArray` therefore resolves each receiver from the GPIO encoded in its
device-tree platform name (`ir-receiver@<hex-gpio>`) below `/sys/class/rc`.

Use `tower ir-receivers` to show the configured array and its current live
device mappings. The command returns a non-zero exit status if any receiver is
missing.

Use `tower ir-capture <device-name> <command-name> [seconds]` to record all six
resolved LIRC devices simultaneously. The default duration is eight seconds.
Each receiver gets its own filtered `.mode2` file below a timestamped directory
in `captures/ir/`. This is the diagnostic capture path; it deliberately does
not save or replace a learned command.

Use `tower ir-analyze [capture-directory|latest]` to decode a saved capture
group and compare the receivers. When no directory is supplied, Tower analyzes
the latest capture. The analyzer supports:

- Siemens/Ruwido
- NEC and NECx, including repeat frames
- Sony SIRC-12
- Kaseikyo-Denon with manufacturer parity and checksum validation

Tower ranks captures by valid-frame consistency, timing quality, and the
protocol's expected carrier frequency. A receiver is only eligible for
learning when its result is `CLEAN`.

Use `tower learn <device-name> <command-name> [seconds] [--force]` for the
complete learning path. Tower verifies that all six receivers are available,
captures them simultaneously, analyzes the group, selects the best clean
receiver, extracts one validated initial frame, and saves it in the existing
raw replay format. The record also contains decoded protocol, address, command,
carrier, receiver, and source-capture metadata.

Existing commands are protected unless `--force` is supplied. A forced
replacement is installed only after successful capture and analysis, and the
previous record is preserved as `.tower-learn-backup`.

The complete path was verified with KPN Power: GPIO25 / TSOP38256 at 56 kHz
produced 12/12 valid Siemens frames (`0x250` / `0x0B`). The saved representative
frame replayed successfully through `Tower-IR-TX-001`.
