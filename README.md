# Valhalla

Valhalla is a native macOS Samsung firmware flashing UI built around the
Heimdall command-line backend. It accepts Odin-style BL, AP, CP, CSC, and
USERDATA packages, verifies appended MD5 checksums, inspects archives, unpacks
LZ4 payloads, reads the connected device PIT, and only builds a flash command
when every payload has one authoritative PIT match.

## Safety model

- No automatic partition-name guesses.
- Imported PITs are inspection-only; flashing always uses a live device PIT.
- No repartition support in this MVP.
- No device write until the user types `FLASH`.
- Failed or unmapped payloads block the operation.
- The full Heimdall result is retained in the local session log.

The app does **not** bypass Samsung bootloader locks, Factory Reset Protection,
or device security. Use firmware made for the exact model and bootloader
revision.

## Requirements

- macOS 13 or later
- Intel or Apple Silicon Mac (the packaged app is universal)
- Heimdall (`brew install heimdall`)
- LZ4 (`brew install lz4`) for modern Samsung packages
- A Samsung phone already booted into Download Mode

## Build and run

```sh
swift test
swift run Valhalla
```

Package a launchable app bundle:

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/Valhalla.app
```

The generated app is ad-hoc signed for local use.

## Current scope

Valhalla is an MVP, not a drop-in claim of compatibility with every Samsung
generation. Heimdall 1.4.2 is the current local backend. Validate on a
non-critical, supported device before trusting it with daily-driver hardware.
