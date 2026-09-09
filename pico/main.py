from machine import Pin, PWM, reset
import binascii
import gc
import hashlib
import network
import os
import rp2
import select
import socket
import time

from wifi_config import WIFI_COUNTRY, WIFI_PASSWORD, WIFI_SSID

DEFAULT_IR_CARRIER_KHZ = 38
MIN_IR_CARRIER_KHZ = 20
MAX_IR_CARRIER_KHZ = 60
IR_DUTY = 21845  # Approximately 33%.
MIN_IR_DUTY_PERCENT = 10
MAX_IR_DUTY_PERCENT = 80
COMMAND_PORT = 42101
MAX_COMMAND_BYTES = 131072
MAX_UPDATE_BYTES = 90000
HOSTNAME = "tower-pico"

# Tower-IR-TX-001 through Tower-IR-TX-006 map to GP1 through GP6.
OUTPUT_PINS = (1, 2, 3, 4, 5, 6)
outputs = [Pin(number, Pin.OUT, value=0) for number in OUTPUT_PINS]
led = Pin("LED", Pin.OUT, value=0)


# Each program drives GP1 through GP6 as one six-bit value.  The state
# machine checks its FIFO once per carrier cycle; a non-zero value begins a
# mark on every selected output and zero begins a space.  This keeps both the
# carrier phase and the raw-code envelope aligned across all transmitters.
@rp2.asm_pio(out_init=(rp2.PIO.OUT_LOW,) * 6)
def carrier_10():
    wrap_target()
    pull(noblock)
    mov(x, osr)
    mov(pins, x)
    mov(pins, null) [6]
    wrap()


@rp2.asm_pio(out_init=(rp2.PIO.OUT_LOW,) * 6)
def carrier_20():
    wrap_target()
    pull(noblock)
    mov(x, osr)
    mov(pins, x) [1]
    mov(pins, null) [5]
    wrap()


@rp2.asm_pio(out_init=(rp2.PIO.OUT_LOW,) * 6)
def carrier_30():
    wrap_target()
    pull(noblock)
    mov(x, osr)
    mov(pins, x) [2]
    mov(pins, null) [4]
    wrap()


@rp2.asm_pio(out_init=(rp2.PIO.OUT_LOW,) * 6)
def carrier_33():
    wrap_target()
    pull(noblock)
    mov(x, osr)
    mov(pins, x) [1]
    mov(pins, null) [1]
    wrap()


@rp2.asm_pio(out_init=(rp2.PIO.OUT_LOW,) * 6)
def carrier_40():
    wrap_target()
    pull(noblock)
    mov(x, osr)
    mov(pins, x) [3]
    mov(pins, null) [3]
    wrap()


@rp2.asm_pio(out_init=(rp2.PIO.OUT_LOW,) * 6)
def carrier_50():
    wrap_target()
    pull(noblock)
    mov(x, osr)
    mov(pins, x) [4]
    mov(pins, null) [2]
    wrap()


@rp2.asm_pio(out_init=(rp2.PIO.OUT_LOW,) * 6)
def carrier_60():
    wrap_target()
    pull(noblock)
    mov(x, osr)
    mov(pins, x) [5]
    mov(pins, null) [1]
    wrap()


def all_off():
    for output in outputs:
        output.init(Pin.OUT, value=0)


def validate_raw(carrier_khz, durations, duty_percent):
    if (carrier_khz < MIN_IR_CARRIER_KHZ or
            carrier_khz > MAX_IR_CARRIER_KHZ):
        raise ValueError("INVALID_CARRIER_KHZ")

    if duty_percent and (duty_percent < MIN_IR_DUTY_PERCENT or
                         duty_percent > MAX_IR_DUTY_PERCENT):
        raise ValueError("INVALID_DUTY_PERCENT")

    if not durations:
        raise ValueError("NO_DURATIONS")

    for duration in durations:
        if duration < 1 or duration > 100000:
            raise ValueError("INVALID_DURATION")


def synchronized_carrier(duty_percent):
    # Calibration and stored device profiles use these exact duty values.
    # Seven four-instruction programs fit together in one 32-instruction PIO.
    programs = {
        10: (carrier_10, 10),
        20: (carrier_20, 10),
        30: (carrier_30, 10),
        33: (carrier_33, 6),
        40: (carrier_40, 10),
        50: (carrier_50, 10),
        60: (carrier_60, 10),
    }

    effective_duty = duty_percent if duty_percent else 33
    if effective_duty not in programs:
        raise ValueError("UNSUPPORTED_SYNC_DUTY_PERCENT")

    return programs[effective_duty]


def send_raw(transmitter, carrier_khz, durations, duty_percent=0):
    if transmitter < 1 or transmitter > len(outputs):
        raise ValueError("INVALID_TRANSMITTER")

    validate_raw(carrier_khz, durations, duty_percent)

    if duty_percent:
        mark_duty = int(65535 * duty_percent / 100)
    else:
        mark_duty = IR_DUTY

    output = outputs[transmitter - 1]
    pwm = PWM(output)
    pwm.freq(carrier_khz * 1000)
    pwm.duty_u16(0)
    gc.collect()

    try:
        for index, duration in enumerate(durations):
            pwm.duty_u16(mark_duty if index % 2 == 0 else 0)
            time.sleep_us(duration)
    finally:
        pwm.duty_u16(0)
        pwm.deinit()
        output.init(Pin.OUT, value=0)


def send_raw_multi(transmitters, carrier_khz, durations, duty_percent=0):
    if not transmitters:
        raise ValueError("NO_TRANSMITTERS")

    output_mask = 0
    for transmitter in transmitters:
        if transmitter < 1 or transmitter > len(outputs):
            raise ValueError("INVALID_TRANSMITTER")
        output_mask |= 1 << (transmitter - 1)

    validate_raw(carrier_khz, durations, duty_percent)
    program, cycles_per_carrier = synchronized_carrier(duty_percent)
    state_machine = None
    gc.collect()

    try:
        state_machine = rp2.StateMachine(
            0,
            program,
            freq=carrier_khz * 1000 * cycles_per_carrier,
            out_base=outputs[0],
        )
        state_machine.put(output_mask)
        state_machine.active(1)

        for index, duration in enumerate(durations):
            if index > 0:
                state_machine.put(output_mask if index % 2 == 0 else 0)
            time.sleep_us(duration)

        # Let the state machine consume the final zero before stopping it.
        state_machine.put(0)
        time.sleep_us(((1000 + carrier_khz - 1) // carrier_khz) + 10)
    finally:
        if state_machine is not None:
            state_machine.active(0)
        all_off()
        gc.collect()




def test_transmitter(transmitter):
    send_raw(
        transmitter,
        DEFAULT_IR_CARRIER_KHZ,
        (10000, 10000, 10000, 10000, 10000),
    )


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
            duty_percent = 0

            if len(parts) == 3:
                # Compatibility with Tower versions that always used 38 kHz.
                transmitter = int(parts[1])
                carrier_khz = DEFAULT_IR_CARRIER_KHZ
                durations_text = parts[2]
            elif len(parts) == 4:
                transmitter = int(parts[1])
                carrier_khz = int(parts[2])
                durations_text = parts[3]
            elif len(parts) == 5:
                transmitter = int(parts[1])
                carrier_khz = int(parts[2])
                duty_percent = int(parts[3])
                durations_text = parts[4]
            else:
                raise ValueError(
                    "USAGE_SEND_TRANSMITTER_CARRIER_[DUTY_]DURATIONS")

            durations = [
                int(value)
                for value in durations_text.split(",")
            ]

            send_raw(transmitter, carrier_khz, durations, duty_percent)
            return "OK SEND " + str(transmitter), False

        if command == "SEND_MULTI":
            duty_percent = 0

            if len(parts) == 4:
                transmitters_text = parts[1]
                carrier_khz = int(parts[2])
                durations_text = parts[3]
            elif len(parts) == 5:
                transmitters_text = parts[1]
                carrier_khz = int(parts[2])
                duty_percent = int(parts[3])
                durations_text = parts[4]
            else:
                raise ValueError(
                    "USAGE_SEND_MULTI_OUTPUTS_CARRIER_[DUTY_]DURATIONS")

            transmitters = []
            for value in transmitters_text.split(","):
                transmitter = int(value)
                if transmitter not in transmitters:
                    transmitters.append(transmitter)

            durations = [
                int(value)
                for value in durations_text.split(",")
            ]

            send_raw_multi(
                transmitters,
                carrier_khz,
                durations,
                duty_percent,
            )
            return "OK SEND_MULTI " + transmitters_text, False

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
