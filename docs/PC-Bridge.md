# Tower PC Control Bridge

Tower exposes a PC-facing interface from the long-running `tower service`
process. The Windows client shows live sensor measurements, all paired RF power
devices, and every logical device with recorded IR commands.

## Start the service for a manual test

Set a private token and start Tower from the project directory:

```bash
TOWER_API_TOKEN='replace-with-a-long-private-token' ./build/tower service
```

The API listens on TCP port `8080` on the local network. Do not forward this
port through the router.

## Test from Windows PowerShell

Replace the address and token:

```powershell
$headers = @{ Authorization = 'Bearer replace-with-a-long-private-token' }
Invoke-RestMethod http://PI3A:8080/api/v1/rf/devices -Headers $headers
```

## Windows remote

Copy the complete `windows` directory to the Windows PC and double-click:

```text
Start-Tower-Control.cmd
```

On first launch, enter the Tower address and the same token. The program saves
them in `%APPDATA%\Tower\client.json`.

The program contains three pages:

- Sensors: aquarium temperature and every BME688 measurement exposed by Tower.
- RF Power: individual On/Off buttons plus combined All On and All Off.
- IR Remotes: logical devices and their enabled recorded commands. Newly
  recorded devices appear without changing the Windows program.

The old `Start-Tower-RF-Remote.cmd` launcher remains as a compatibility shortcut
and opens the new Tower Control program.

Delete `client.json` to enter a different address or token on the next launch.

## Endpoints

- `GET /api/v1/status` - unauthenticated health check.
- `GET /api/v1/sensors` - authenticated current readings from managed sensors.
- `GET /api/v1/devices` - authenticated logical devices and commands.
- `POST /api/v1/execute` - authenticated logical command execution with JSON
  fields `device` and `command`.
- `GET /api/v1/rf/devices` - authenticated paired-device list.
- `POST /api/v1/rf/send` - authenticated RF action with JSON fields `device`
  and `action` (`on` or `off`). Tower validates both fields, launches the
  existing `tower send <device> <on|off>` CLI path without a shell, waits for
  its exit status, and only then reports success.
- `POST /api/v1/rf/all` - authenticated `on` or `off` action for every paired RF
  power definition. The response contains one result per device.
