# Tower PC Bridge

Tower v0.10.10 provides the first PC-facing interface to the long-running
`tower service` process. This milestone covers the already-built and tested RF
power definitions. IR remote and command selection will be added later.

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
Start-Tower-RF-Remote.cmd
```

On first launch, enter the Tower address and the same token. The program saves
them in `%APPDATA%\Tower\client.json`. It retrieves all RF device definitions from
Tower and creates On/Off buttons from that response.

Delete `client.json` to enter a different address or token on the next launch.

## Endpoints

- `GET /api/v1/status` - unauthenticated health check.
- `GET /api/v1/rf/devices` - authenticated paired-device list.
- `POST /api/v1/rf/send` - authenticated RF action with JSON fields `device`
  and `action` (`on` or `off`). Tower validates both fields, launches the
  existing `tower send <device> <on|off>` CLI path without a shell, waits for
  its exit status, and only then reports success.
