# RF Power Add / Pair Wizard

RF power provisioning is owned by the Tower/Pi and exposed to both CLI and
Windows through shared `RFProvisioningService` logic.

## Current sequence

```text
Tower-RF-Power-M2-001 -> 0x123456
Tower-RF-Power-M2-002 -> 0x123457
Tower-RF-Power-M2-003 -> 0x123458
Tower-RF-Power-M2-004 -> 0x123459
```

Next suggestion:

```text
Tower-RF-Power-M2-005.rf
0x12345A
```

The transmitter IDs are hexadecimal.

## New modern RF file defaults

```text
protocol=kaku_ac
description=Modern KlikAanKlikUit self-learning receiver
unit=1
gpio=24
status=unpaired
pulse=260
repeat=16
```

The wizard supplies `device_name` and the editable `transmitter_id`.

## Pairing

1. Put/power receiver into learn mode.
2. READY sends ON immediately.
3. The existing sender repeats the complete packet 16 times.
4. Confirm that receiver switched ON.
5. Tower sends OFF using the same transmitter ID + unit.
6. Confirm receiver switched OFF.
7. Tower persists `status=paired`.

If skipped or not confirmed, the file remains `status=unpaired`.

## CLI

```bash
tower rf next
tower rf add
tower rf pair Tower-RF-Power-M2-005
```

## API

```text
GET  /api/v1/rf/modern/next
POST /api/v1/rf/create
POST /api/v1/rf/pair/start
POST /api/v1/rf/pair/status
```
