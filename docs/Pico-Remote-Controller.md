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
| `Tower-IR-TX-001` | 1 | GP0 |
| `Tower-IR-TX-002` | 2 | GP1 |
| `Tower-IR-TX-003` | 3 | GP2 |
| `Tower-IR-TX-004` | 4 | GP3 |
| `Tower-IR-TX-005` | 5 | GP4 |
| `Tower-IR-TX-006` | 6 | GP5 |

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

## 5. Move the Pico to the separate 5 V supply

Only do this after Wi-Fi is working:

- Disconnect the Pico USB cable from the Raspberry Pi.
- Adapter `+5 V` goes to Pico `VSYS` (physical pin 39).
- Adapter ground goes to a Pico `GND` pin.
- The transmitter board uses the same adapter `+5 V` and ground.
- Pico GP0 remains connected to the input of `Tower-IR-TX-001`.
- Do not connect this adapter's `+5 V` to the Raspberry Pi 5 V rail.

The shared ground between the Pico and transmitter circuit is required.

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

The firmware keeps reconnecting if Wi-Fi is temporarily lost.
