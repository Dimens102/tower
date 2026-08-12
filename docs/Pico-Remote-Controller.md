# Tower Pico 2 W Remote Controller

## Result

The Pico 2 W joins the normal Wi-Fi network and accepts Tower IR commands over
TCP. Tower always connects to:

```text
192.168.2.30:42101
```

The Pico initially uses DHCP. This lets it appear in the router client list.
Reserve `192.168.2.30` for that Pico in the router and reboot the Pico. No
automatic discovery is used.

## Output mapping

| Tower transmitter | Pico output | Pico pin |
|---|---:|---|
| `Tower-IR-TX-001` | 1 | GP1 |
| `Tower-IR-TX-002` | 2 | GP2 |
| `Tower-IR-TX-003` | 3 | GP3 |
| `Tower-IR-TX-004` | 4 | GP4 |
| `Tower-IR-TX-005` | 5 | GP5 |
| `Tower-IR-TX-006` | 6 | GP6 |

Only `Tower-IR-TX-001` is moved to the Pico by this release. The remaining
existing transmitters keep their Raspberry Pi GPIO assignments.

## 1. Create the private Wi-Fi configuration

On the Raspberry Pi:

```bash
cd ~/Development/rf-tower
cp pico/wifi_config.example.py pico/wifi_config.py
nano pico/wifi_config.py
```

Enter the Wi-Fi SSID and password in `wifi_config.py`. Do not send the password
through chat and do not commit this file. It is excluded by `.gitignore`.

## 2. Upload the firmware while USB is still connected

Keep the Pico connected to the Raspberry Pi by USB and run:

```bash
cd ~/Development/rf-tower
~/.local/bin/mpremote connect /dev/ttyACM0 fs cp pico/wifi_config.py :wifi_config.py
~/.local/bin/mpremote connect /dev/ttyACM0 fs cp pico/main.py :main.py
~/.local/bin/mpremote connect /dev/ttyACM0 reset
```

The Pico connects through DHCP and advertises the hostname `tower-pico` when
supported by its MicroPython build.

## 3. Reserve the final address

Open the router's connected-device list and find `tower-pico` or the newly
connected Pico. Create a DHCP reservation for:

```text
192.168.2.30
```

Reset or power-cycle the Pico after saving the reservation. Confirm that the
router now shows it at `192.168.2.30`.

## 4. Test the TCP service

From the Raspberry Pi:

```bash
python3 -c "import socket; s=socket.create_connection(('192.168.2.30',42101),3); s.sendall(b'PING\n'); print(s.recv(100).decode().strip()); s.close()"
```

Expected result:

```text
PONG
```

## 5. Power the Pico independently

Only do this after Wi-Fi is working:

- Disconnect the Pico USB cable from the Raspberry Pi.
- Adapter `+5 V` goes to Pico `VSYS` (physical pin 39).
- Adapter ground goes to a Pico `GND` pin.
- Do not use the Pico's 5 V rail to power the IR transmitter stage. Power the
  RE909 transmitter boards from their separate regulated 3.3 V rail described
  below.
- Pico GP1 remains connected to the input of `Tower-IR-TX-001`.
- Do not connect this adapter's `+5 V` to the Raspberry Pi 5 V rail.

The Pico supply, external 3.3 V transmitter supply, and transmitter circuit
must share ground.

## Known-good RE909 IR transmitter configuration

This is the proven transmitter configuration tested with the KPN receiver. It
works reliably at room range and can switch the KPN box even when the IR light
is reflected from a wall.

### Power

- Power the IR transmitter stage from a separate regulated **3.3 V** supply.
- The tested supply is a 12 V Plextor adapter feeding an adjustable DC/DC
  converter set to 3.3 V. The adapter can provide up to 3 A; the circuit only
  draws the current it needs.
- Connect the external supply ground to Pico ground. The common ground is
  required for the Pico control signal to work.
- Do not connect the external 3.3 V output to a Pico GPIO.
- Keep the transmitter stage at 3.3 V. The known-good circuit does not need a
  5 V LED supply.

### Driver board and resistor values

Each transmitter uses an RE909 board with a BC817 transistor driver.

| Part | Value / type | Function |
|---|---|---|
| Pico control resistor | 1 kΩ | Series protection between the selected Pico GP output and the RE909 control input |
| RE909 base resistor (`331`) | 330 Ω | Limits BC817 base current |
| RE909 LED resistor (`2R2`) | 2.2 Ω | Limits the pulsed IR LED current |
| RE909 transistor (`6C`) | BC817-40 | Switches the IR LED current; the Pico GPIO only supplies the control signal |
| RE909 base pull-down (`103`) | 10 kΩ | Holds the BC817 off while the Pico output is floating or starting |

The working signal chain is:

```text
Pico GP output -> 1 kΩ -> RE909 input -> 330 Ω -> BC817 base
External 3.3 V -> RE909/BC817 LED stage -> 2.2 Ω -> IR LED -> GND
Pico GND -----------------------------------------------> External GND
```

The transmitter must never be powered directly from a Pico GPIO. The GPIO only
drives the BC817 control path. Tower supplies the carrier saved with each
recording; the confirmed KPN command uses 56 kHz rather than the 38 kHz
fallback.

## 6. Build and test Tower

```bash
cd ~/Development/rf-tower
tb
tower replay Denon VolumeUp Tower-IR-TX-001
```

Tower should report that it is sending through `192.168.2.30` output 1.

## Firmware files

- `pico/main.py`: Wi-Fi connection, TCP command service, and IR output.
- `pico/wifi_config.example.py`: safe template committed to the project.
- `pico/wifi_config.py`: private local credentials uploaded to the Pico.

The firmware keeps reconnecting if Wi-Fi is temporarily lost. Tower includes
the `carrier_khz` stored with each raw IR recording in every Pico send command,
so the Pico changes its PWM carrier automatically for each transmission. Older
recordings without carrier metadata use 38 kHz.

## Tower service startup check

During `tower service` startup, the LCD shows a Tower Pico check after the
sensor and scheduler check and before the GPIO26 check.

Tower reuses `PicoController::initialize()` for this check. It connects to
`192.168.2.30:42101`, sends `PING`, and only reports the Pico as connected when
the response is exactly `PONG`.

The LCD result is either:

```text
[pico] connected
192.168.2.30
```

or:

```text
[pico] unavailable
192.168.2.30
```

An unavailable Pico is logged as a warning and does not stop the Tower service.
