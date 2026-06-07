# Tactical Mesh

Flutter hybrid prototype for a tactical Android/iOS app with Meshtastic position sharing, internet PTT voice, and future Android Auto / CarPlay support.

## Current Prototype

- Ranger Green dark tactical UI.
- Map screen with simulated Meshtastic nodes.
- Own position panel with MGRS, latitude, longitude, altitude.
- Local and UTC clock.
- Team list with distance, bearing, battery, and last seen status.
- Message view with LoRa text and internet PTT system messages.
- Hold-to-talk PTT control for the internet voice channel.
- System screen with Meshtastic BLE, PTT server, and car mode status.
- Adaptive portrait and landscape layouts.
- Font size slider in system settings for all operational UI text except the main title.
- Meshtastic BLE service scaffold using the official BLE service and ToRadio/FromRadio/FromNum characteristics.
- Meshtastic packet diagnostics in system settings: packet count, decoded NodeInfo/Position/Text events, last RX time, packet size, and hex preview.
- Encrypted PTT frame service using AES-GCM 256.
- Local auth service with demo roles (`operator`, `commander`, `medic`), session chip, and logout.
- Communication groups with role-based access: ALPHA, BRAVO, MED, COMMAND.
- PTT channel access is derived from the authenticated session and selected group; each group gets its own AES-GCM key material.

## Target Architecture

- `Flutter/Dart`: main mobile UI, shared app state, map, team, messages, settings.
- `Kotlin`: Android Bluetooth LE, foreground audio service, Android Auto templates.
- `Swift`: iOS Bluetooth LE, audio session, CallKit integration, CarPlay templates.
- `Meshtastic BLE`: LILYGO T-Beam 868 MHz, `ToRadio` / `FromRadio` protobuf messages.
- `Internet PTT`: WebRTC/LiveKit style server, room tokens, channel floor control, AES-GCM encrypted voice frames.
- `Backend`: authentication, teams, channels, operation data, gateway sync.

## Layout Modes

- `Portrait`: bottom navigation, one primary view at a time, full-width PTT bar.
- `Landscape`: map mode uses maximum map width; team/message/system modes keep the map on the left and show a right-side detail panel.

## Next Implementation Steps

1. Replace the focused manual Meshtastic protobuf decoder with generated classes when `protoc` is available in CI.
2. Replace demo node data with live `Position` and `NodeInfo` packets.
3. Add MGRS conversion library or internal converter.
4. Add LiveKit/WebRTC PTT transport and backend token/key endpoint.
5. Add Android foreground audio service and iOS audio session handling.
6. Add native Android Auto and CarPlay modules with restricted car-safe UI.

## Run

```sh
/opt/homebrew/share/flutter/bin/flutter run
```

For local web preview:

```sh
/opt/homebrew/share/flutter/bin/flutter run -d web-server --web-hostname 127.0.0.1 --web-port 53621
```
