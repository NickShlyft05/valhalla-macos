# Valhalla

Valhalla is a native macOS Samsung firmware flashing UI built around the
Heimdall command-line backend. It accepts Odin-style BL, AP, CP, CSC, and
USERDATA packages, verifies appended MD5 checksums, inspects archives, unpacks
LZ4 payloads, reads the connected device PIT, and only builds a flash command
when every payload has one authoritative PIT match.

Valhalla also includes a Samsung Bootloader Unlock Assistant. It uses ADB to
identify the connected phone, inspect advisory OEM-unlock and flash-lock state,
open Developer options, and request a reboot into Samsung Download Mode. The
irreversible unlock approval remains a physical action on the phone.

## Safety model

- No automatic partition-name guesses.
- Imported PITs are inspection-only; flashing always uses a live device PIT.
- No repartition support in this MVP.
- No device write until the user types `FLASH`.
- Failed or unmapped payloads block the operation.
- Bootloader preparation requires ownership, backup, FRP-credential, and Knox
  acknowledgements plus the phrase `ERASE AND UNLOCK`.
- Missing OEM Unlock, KG/RMM restrictions, and FRP are treated as hard stops,
  never as bypass opportunities.
- Bootloader unlock and firmware flashing remain separate actions.
- The full Heimdall result is retained in the local session log.

The app does **not** bypass Factory Reset Protection, Knox Guard, RMM, carrier
restrictions, Samsung account locks, or device security. A supported
bootloader unlock factory-resets the phone, and later running unauthorized code
can permanently trip the Knox Warranty Bit.

## Requirements

- macOS 13 or later
- Intel or Apple Silicon Mac (the packaged app is universal)
- Heimdall (`brew install heimdall`)
- Android Platform Tools (`brew install android-platform-tools`)
- LZ4 (`brew install lz4`) for modern Samsung packages
- A Samsung phone with USB debugging enabled or already in Download Mode

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
