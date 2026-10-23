# Tactical Mesh

Flutter hybrid prototype for a tactical Android/iOS app with Meshtastic position sharing, encrypted internet PTT voice, real map display, and future Android Auto / CarPlay support.

[![Flutter CI](https://github.com/CaveBushman/fpmc_tactical_car_app/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/CaveBushman/fpmc_tactical_car_app/actions/workflows/flutter-ci.yml)

## Current Prototype

- Ranger Green dark tactical UI.
- Real OpenStreetMap raster map with local Flutter map tile cache.
- Team map with live GPS own position (follow mode + recenter), demo baseline nodes, Meshtastic packet updates, links, range circles, and tactical grid overlay.
- Own position panel with fully readable MGRS fields, latitude, longitude, altitude.
- Local and UTC clock.
- Team list with distance, bearing, battery, and last seen status that ages to STALE/LOST.
- Message delivery status (sent / delivered / failed) with resend for messages the T-Beam did not take.
- Message view with Meshtastic group messages, direct messages, quick actions, and internet PTT system messages.
- Quick `NA POZICI` message includes full MGRS, latitude, and longitude.
- Hold-to-talk PTT control for the internet voice channel.
- System screen with Meshtastic BLE, PTT server, and car mode status.
- Adaptive portrait and landscape layouts.
- Font size slider in system settings for all operational UI text except the main title.
- Meshtastic BLE service using the official BLE service and ToRadio/FromRadio/FromNum characteristics.
- Meshtastic packet diagnostics in system settings: packet count, decoded NodeInfo/Position/Text events, last RX time, packet size, and hex preview.
- Focused Meshtastic protobuf reader/writer for MyNodeInfo, NodeInfo, Position, TextMessage, Routing (ACK/NAK) and want_config handshake.
- Encrypted PTT frame service using AES-GCM 256.
- Local auth service with demo roles (`operator`, `commander`, `medic`), password check (demo password `<user>-2026`, e.g. `operator-2026`), lockout after 5 failed attempts, session chip, and logout.
- Communication groups with role-based access: ALPHA, BRAVO, MED, COMMAND.
- PTT channel access is derived from the authenticated session and selected group; each group gets its own AES-GCM key material.
- Node/message state persisted locally, AES-GCM encrypted with a key in the platform keystore, wiped on logout.
- GitHub Actions CI for dependency install, static analysis, tests, web build, and Android debug APK build.

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

## Meshtastic BLE

The app targets a LILYGO T-Beam 868 MHz running Meshtastic over Bluetooth LE.

Configured UUIDs:

- Service: `6ba1b218-15a8-461f-9fa8-5dcae273eafd`
- ToRadio: `f75c76d2-129e-4dad-a1dd-7866124401e7`
- FromRadio: `2c55e69e-4993-11ed-b878-0242ac120002`
- FromNum: `ed9da18c-a800-4f66-a670-aa7547e34453`

Current packet support:

- Receive `NodeInfo` and update node identity.
- Receive `Position` and update map/team state.
- Receive `TextMessage` and add it to the selected communication group.
- Send group text messages through Meshtastic `ToRadio`.
- Send direct text messages with destination node and ack request.

## Map Data

The prototype currently uses public OpenStreetMap raster tiles for local development. Do not use public OSM tile servers as the default production tile backend. For field use, prepare offline tile packs or a controlled tile service such as MapTiler, Mapbox, Thunderforest, or a private tile server.

## Security Notes

- PTT frame encryption uses AES-GCM 256 in the prototype.
- Demo auth is local and must be replaced with server-backed authentication before real deployment.
- Group keys are derived locally for prototype flow validation; production should use authenticated key distribution and rotation.
- Meshtastic LoRa payload security should be aligned with the operation channel configuration on the devices.

## Next Implementation Steps

1. Replace the focused manual Meshtastic protobuf layer with generated classes when `protoc` is available in CI.
2. Add offline map package management by operation area.
3. Add LiveKit/WebRTC PTT transport and backend token/key endpoint.
4. Add Android foreground audio service and iOS audio session handling.
5. Add native Android Auto and CarPlay modules with restricted car-safe UI.
6. Add server-backed users, teams, operation groups, device binding, and audit logs.
7. Add end-to-end integration tests with recorded Meshtastic BLE packets.

## Code Layout

- `lib/main.dart` – entry point and map tile cache setup.
- `lib/app.dart` – `MaterialApp`, home screen shell (layout, navigation, logout confirmation).
- `lib/controllers/tactical_controller.dart` – `ChangeNotifier` owning session, nodes, messages, GPS, Meshtastic and PTT services.
- `lib/models/` – mesh node, messaging, navigation/waypoint models and `geo.dart` (distance, bearing, MGRS).
- `lib/screens/` – login, map, team, messages, systems pages.
- `lib/widgets/` – shared, node, position and navigation widgets.
- `lib/services/` – BLE, protobuf, auth, crypto, location and storage services.

## Run

```sh
flutter run
```

For local web preview:

```sh
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 53621
```

## Verify

```sh
flutter analyze
flutter test
flutter build web --release
```
