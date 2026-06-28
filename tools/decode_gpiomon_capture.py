#!/usr/bin/env python3
import sys
import re
from pathlib import Path

PROTOCOLS = [
    # protocol, pulse, sync(high,low), zero(high,low), one(high,low), inverted
    (1, 350, (1, 31),  (1, 3),  (3, 1),  False),
    (2, 650, (1, 10),  (1, 2),  (2, 1),  False),
    (3, 100, (30, 71), (4, 11), (9, 6),  False),
    (4, 380, (1, 6),   (1, 3),  (3, 1),  False),
    (5, 500, (6, 14),  (1, 2),  (2, 1),  False),
    (6, 450, (23, 1),  (1, 2),  (2, 1),  True),
    (7, 150, (2, 62),  (1, 6),  (6, 1),  False),
    (8, 200, (3, 130), (7, 16), (3, 16), False),
    (9, 200, (130, 7), (16, 7), (16, 3), True),
    (10,365, (18, 1),  (3, 1),  (1, 3),  True),
    (11,270, (36, 1),  (1, 2),  (2, 1),  True),
    (12,320, (36, 1),  (1, 2),  (2, 1),  True),
]

TOLERANCE = 0.60
MIN_BITS = 8
MAX_BITS = 64

def parse_file(path):
    times = []
    for line in Path(path).read_text(errors="ignore").splitlines():
        m = re.match(r"\s*([0-9]+\.[0-9]+)\s+(rising|falling)", line)
        if m:
            times.append(float(m.group(1)))
    return times

def durations_us(times):
    return [(times[i] - times[i-1]) * 1_000_000 for i in range(1, len(times))]

def close(a, b, tolerance=TOLERANCE):
    return abs(a - b) <= b * tolerance

def decode_frame(frame):
    results = []

    for proto, pulse, sync, zero, one, inverted in PROTOCOLS:
        # Try both normal and shifted starts because gpiomon may start inside a frame.
        for start in range(0, min(4, len(frame))):
            d = frame[start:]

            if len(d) < 16:
                continue

            # rc-switch estimates pulse from first sync duration.
            sync_max = max(sync)
            delay = d[0] / sync_max
            if delay < 50 or delay > 2000:
                continue

            bits = ""
            first_data = 2 if inverted else 1

            i = first_data
            while i + 1 < len(d):
                hi = d[i]
                lo = d[i+1]

                if close(hi, delay * zero[0]) and close(lo, delay * zero[1]):
                    bits += "0"
                elif close(hi, delay * one[0]) and close(lo, delay * one[1]):
                    bits += "1"
                else:
                    break

                i += 2

            if MIN_BITS <= len(bits) <= MAX_BITS:
                value = int(bits, 2)
                results.append({
                    "protocol": proto,
                    "delay_us": round(delay, 1),
                    "bits_len": len(bits),
                    "bits": bits,
                    "value": value,
                    "hex": hex(value),
                })

    return results

def split_frames(durations, gap_us=5000):
    frames = []
    cur = []

    for d in durations:
        if d > gap_us:
            if len(cur) > 10:
                frames.append(cur)
            cur = [d]
        else:
            cur.append(d)

    if len(cur) > 10:
        frames.append(cur)

    return frames

def main():
    if len(sys.argv) != 2:
        print("Usage: decode_gpiomon_capture.py <capture.txt>")
        sys.exit(1)

    path = sys.argv[1]
    times = parse_file(path)
    durs = durations_us(times)
    frames = split_frames(durs)

    print(f"File: {path}")
    print(f"Edges: {len(times)}")
    print(f"Durations: {len(durs)}")
    print(f"Frames found: {len(frames)}")

    seen = set()
    for idx, frame in enumerate(frames[:100], start=1):
        results = decode_frame(frame)
        for r in results:
            key = (r["protocol"], r["bits_len"], r["value"])
            if key in seen:
                continue
            seen.add(key)

            print()
            print(f"Frame {idx}")
            print(f"  protocol : {r['protocol']}")
            print(f"  delay_us : {r['delay_us']}")
            print(f"  bitlen   : {r['bits_len']}")
            print(f"  value    : {r['value']}")
            print(f"  hex      : {r['hex']}")
            print(f"  bits     : {r['bits']}")

    if not seen:
        print("No rc-switch style protocol decoded.")

if __name__ == "__main__":
    main()
