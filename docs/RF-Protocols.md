# RF Protocol Notes

This document records RF families, timing assumptions, pairing behavior, and verification status.

## Current scope

Tower currently supports stored RF power-device definitions and transmission through the RF sender layer.

## Device record fields

Current records may include:

- model or record ID
- protocol/family
- transmitter ID
- unit
- GPIO
- pairing status
- pulse length
- repeat count
- friendly device name

## Modern KAKU / M2 family

Known working family defaults currently used:

```text
pulse=260
repeat=16
```

These values may be inherited by an unpaired device record to keep the family configuration consistent.

Inherited values must not be described as individually verified until the physical receiver has been paired and tested.

### Current verification note

`Tower-RF-Power-M2-004` uses inherited M2-family timing values. They should be verified once the spare receiver is paired.

## Documentation rule

For every supported RF family, record:

- protocol/family name
- required addressing fields
- known pulse ranges
- repeat behavior
- pairing procedure
- tested transmitters and receivers
- exceptions or device-specific timing
- verification status

## Layering

RF protocol encoding belongs in the RF driver/protocol layer.

Friendly names, locations, and logical commands belong in the device database.

Automation rules should never contain transmitter IDs, raw timings, or GPIO details directly.


---

## RF receiver diagnostics checkpoint (unreleased)

The local work-in-progress receiver diagnostics target the Aurel RX-4MM5-F.

Provisional input mapping:

```text
DATA = GPIO4
RSSI = ADS1115 AIN0
```

Current diagnostic capabilities:

- Rising and falling GPIO-edge detection.
- Edge-count reporting per second through `tower monitor`.
- RSSI voltage output through the modified `tower receive`.
- Pulse-interval output in microseconds through the modified `tower receive`.

These capabilities do not yet constitute protocol learning or decoding.

A future capture record should include at least:

- Capture timestamp.
- GPIO DATA pulse timings.
- Total capture duration.
- Edge count.
- RSSI noise floor.
- RSSI peak.
- RSSI average.
- Detection threshold used.
- Repeat count or repeated-frame candidates.
- Decoder result and confidence, when available.
- Hardware input mapping used for the capture.

Before protocol work continues, Tower must first reliably determine transmission boundaries by combining RSSI activity with the digital edge stream.
