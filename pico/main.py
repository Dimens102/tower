from machine import Pin, PWM, reset
import binascii
import gc
import hashlib
import network
import os
import select
import socket
import time

from wifi_config import WIFI_COUNTRY, WIFI_PASSWORD, WIFI_SSID

IR_FREQUENCY = 38000
IR_DUTY = 21845  # Approximately 33%.
COMMAND_PORT = 42101
MAX_COMMAND_BYTES = 131072
MAX_UPDATE_BYTES = 90000
HOSTNAME = "tower-pico"

# Tower-IR-TX-001 through Tower-IR-TX-006 map to GP1 through GP6.
OUTPUT_PINS = (1, 2, 3, 4, 5, 6)
outputs = [Pin(number, Pin.OUT, value=0) for number in OUTPUT_PINS]
led = Pin("LED", Pin.OUT, value=0)


def all_off():
    for output in outputs:
        output.init(Pin.OUT, value=0)


def send_raw(transmitter, durations):
    if transmitter < 1 or transmitter > len(outputs):
        raise ValueError("INVALID_TRANSMITTER")

    if not durations:
        raise ValueError("NO_DURATIONS")

    for duration in durations:
        if duration < 1 or duration > 100000:
            raise ValueError("INVALID_DURATION")

    output = outputs[transmitter - 1]
    pwm = PWM(output)
    pwm.freq(IR_FREQUENCY)
    pwm.duty_u16(0)
    gc.collect()

    try:
        for index, duration in enumerate(durations):
            pwm.duty_u16(IR_DUTY if index % 2 == 0 else 0)
            time.sleep_us(duration)
    finally:
        pwm.duty_u16(0)
        pwm.deinit()
        output.init(Pin.OUT, value=0)


def test_transmitter(transmitter):
    send_raw(transmitter, (10000, 10000, 10000, 10000, 10000))


def sha256_hex(data):
    return binascii.hexlify(hashlib.sha256(data).digest()).decode()


def update_key():
    # The Wi-Fi password itself is never sent. Its SHA-256 digest is used as
    # the update key. The update service is intended for a trusted home LAN.
    return sha256_hex(WIFI_PASSWORD.encode())


def remove_if_present(path):
    try:
        os.remove(path)
    except OSError:
        pass


def install_main_update(key, expected_size, expected_digest, encoded):
    if key != update_key():
        raise ValueError("UPDATE_AUTH_FAILED")

    if expected_size < 1 or expected_size > MAX_UPDATE_BYTES:
        raise ValueError("INVALID_UPDATE_SIZE")

    try:
        source = binascii.a2b_base64(encoded)
    except (ValueError, TypeError):
        raise ValueError("INVALID_UPDATE_ENCODING")

    if len(source) != expected_size:
        raise ValueError("UPDATE_SIZE_MISMATCH")

    if sha256_hex(source) != expected_digest.lower():
        raise ValueError("UPDATE_DIGEST_MISMATCH")

    try:
        compile(source.decode(), "main.py", "exec")
    except (SyntaxError, UnicodeError):
        raise ValueError("UPDATE_INVALID_PYTHON")

    temporary_path = "main.py.new"
    backup_path = "main.py.bak"

    remove_if_present(temporary_path)

    with open(temporary_path, "wb") as update_file:
        update_file.write(source)
        update_file.flush()

    # Verify the bytes once more after writing them to flash.
    with open(temporary_path, "rb") as update_file:
        if sha256_hex(update_file.read()) != expected_digest.lower():
            remove_if_present(temporary_path)
            raise ValueError("UPDATE_FLASH_VERIFY_FAILED")

    remove_if_present(backup_path)
    os.rename("main.py", backup_path)

    try:
        os.rename(temporary_path, "main.py")
    except OSError:
        os.rename(backup_path, "main.py")
        raise ValueError("UPDATE_INSTALL_FAILED")

    return "OK UPDATE_MAIN " + expected_digest.lower()


def process_command(line):
    parts = line.split(None, 4)

    if not parts:
        return "ERROR EMPTY_COMMAND", False

    command = parts[0].upper()

    try:
        if command == "PING":
            return "PONG", False

        if command == "STATUS":
            states = "".join(str(pin.value()) for pin in outputs)
            return "STATUS OUTPUTS=" + states, False

        if command == "ALL_OFF":
            all_off()
            return "OK ALL_OFF", False

        if command == "TEST":
            if len(parts) != 2:
                raise ValueError("USAGE_TEST_TRANSMITTER")

            transmitter = int(parts[1])
            test_transmitter(transmitter)
            return "OK TEST " + str(transmitter), False

        if command == "SEND":
            if len(parts) != 3:
                raise ValueError(
                    "USAGE_SEND_TRANSMITTER_DURATIONS")

            transmitter = int(parts[1])
            durations = [
                int(value)
                for value in parts[2].split(",")
            ]

            send_raw(transmitter, durations)
            return "OK SEND " + str(transmitter), False

        if command == "UPDATE_MAIN":
            if len(parts) != 5:
                raise ValueError(
                    "USAGE_UPDATE_MAIN_KEY_SIZE_SHA256_BASE64")

            response = install_main_update(
                parts[1],
                int(parts[2]),
                parts[3],
                parts[4],
            )
            return response, True

        return "ERROR UNKNOWN_COMMAND", False

    except (ValueError, TypeError) as error:
        all_off()
        return "ERROR " + str(error), False


def set_hostname(wlan):
    try:
        network.hostname(HOSTNAME)
        return
    except (AttributeError, OSError):
        pass

    try:
        wlan.config(hostname=HOSTNAME)
    except (AttributeError, OSError):
        pass


def connect_wifi():
    try:
        import rp2
        rp2.country(WIFI_COUNTRY)
    except (ImportError, AttributeError):
        pass

    wlan = network.WLAN(network.STA_IF)
    set_hostname(wlan)
    wlan.active(True)

    while not wlan.isconnected():
        print("TOWER_PICO_WIFI_CONNECTING")
        wlan.connect(WIFI_SSID, WIFI_PASSWORD)

        for _ in range(40):
            if wlan.isconnected():
                break

            led.toggle()
            time.sleep_ms(250)

        led.off()

        if not wlan.isconnected():
            wlan.disconnect()
            time.sleep(2)

    print("TOWER_PICO_WIFI " + wlan.ifconfig()[0])
    return wlan


def create_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", COMMAND_PORT))
    server.listen(2)
    return server


def read_command(client):
    received = bytearray()

    while len(received) < MAX_COMMAND_BYTES:
        chunk = client.recv(min(1024, MAX_COMMAND_BYTES - len(received)))

        if not chunk:
            break

        received.extend(chunk)

        if b"\n" in chunk:
            break

    if b"\n" not in received:
        return None

    return received.split(b"\n", 1)[0].decode().strip()


all_off()
led.on()
time.sleep_ms(200)
led.off()

while True:
    wlan = connect_wifi()
    server = None

    try:
        server = create_server()
        poller = select.poll()
        poller.register(server, select.POLLIN)
        print("TOWER_PICO_READY " + wlan.ifconfig()[0])

        while wlan.isconnected():
            events = poller.poll(1000)

            for source, event in events:
                if source is not server or not event & select.POLLIN:
                    continue

                client, _ = server.accept()
                client.settimeout(15)
                restart_after_response = False

                try:
                    line = read_command(client)

                    if line is None:
                        response = "ERROR COMMAND_TOO_LONG"
                    else:
                        response, restart_after_response = process_command(line)

                    client.sendall((response + "\n").encode())
                except OSError:
                    all_off()
                finally:
                    client.close()

                if restart_after_response:
                    time.sleep_ms(300)
                    reset()

    except OSError as error:
        print("TOWER_PICO_NETWORK_ERROR " + str(error))
        all_off()
        time.sleep(2)

    finally:
        if server is not None:
            server.close()

        wlan.disconnect()
        time.sleep(2)
