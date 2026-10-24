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
- Hold-to-talk PTT over a self-hosted LiveKit server with end-to-end encrypted audio, half-duplex floor control (one speaker at a time, "MLUVÍ …" / "OBSAZENO") and per-group rooms. Without `BACKEND_URL` the app runs in demo mode with local accounts and silent PTT.
- System screen with Meshtastic BLE, PTT server, and car mode status.
- Adaptive portrait and landscape layouts.
- Font size slider in system settings for all operational UI text except the main title.
- Meshtastic BLE service using the official BLE service and ToRadio/FromRadio/FromNum characteristics.
- Meshtastic packet diagnostics in system settings: packet count, decoded NodeInfo/Position/Text events, last RX time, packet size, and hex preview.
- Focused Meshtastic protobuf reader/writer for MyNodeInfo, NodeInfo, Position, TextMessage, Routing (ACK/NAK) and want_config handshake.
- Local auth service with demo roles (`operator`, `commander`, `medic`), password check (demo password `<user>-2026`, e.g. `operator-2026`), lockout after 5 failed attempts, session chip, and logout.
- Communication groups with role-based access: ALPHA, BRAVO, MED, COMMAND.
- Backend (`server/`) issues sessions, LiveKit room tokens limited to the user's groups, and random per-group E2EE keys with commander-triggered rotation; security events go to an audit log.
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

By default the app uses public OpenStreetMap raster tiles, which is fine for development only. Viewed tiles go to flutter_map's HTTP cache (512 MB, 30 days); stale cached tiles are **not** shown offline.

Offline packs (System → Mapy → Stáhnout oblast) download the area around your position (2–25 km, zoom 10–16, max 25 000 tiles) into permanent app storage that never expires; the map reads them before the network. Bulk download is disabled for public OSM tiles ([tile usage policy](https://operations.osmfoundation.org/policies/tiles/)), so configure a provider that allows it:

```sh
flutter run \
  --dart-define=TILE_URL='https://api.maptiler.com/maps/outdoor-v2/256/{z}/{x}/{y}.png?key=YOUR_KEY' \
  --dart-define=TILE_NAME=MapTiler \
  --dart-define=TILE_ATTRIBUTION='MapTiler, OpenStreetMap contributors'
```

Optional: `TILE_MAX_ZOOM` (default 18), `TILE_ALLOW_BULK=false` to disable packs for a custom source. Offline packs are not available on web.

## Security Notes

- PTT frame encryption uses AES-GCM 256 in the prototype.
- With `BACKEND_URL` set, login, PTT room access and group keys come from the backend; the local demo accounts are only used when it is not set.
- PTT audio and floor-control messages are E2EE (LiveKit shared-key AES-GCM) with keys from the backend, so the SFU relays ciphertext only. The backend itself knows the group keys; run it on infrastructure you control.
- Transport replay protection comes from DTLS-SRTP; floor-control messages outside ±30 s of local time are ignored.
- Meshtastic LoRa payload security should be aligned with the operation channel configuration on the devices.

## Next Implementation Steps

1. Replace the focused manual Meshtastic protobuf layer with generated classes when `protoc` is available in CI.
2. Add offline map package management by operation area.
3. Add Android foreground audio service and iOS audio session / CallKit so PTT works with the screen off.
4. Add native Android Auto and CarPlay modules with restricted car-safe UI.
5. Add server-side teams management UI, operation groups, device binding, and audit logs.
6. Add end-to-end integration tests with recorded Meshtastic BLE packets.

## PTT Backend and LiveKit

`server/` is a small Dart (shelf) service, `deploy/` a docker-compose stack with LiveKit:

```sh
cd deploy
cp .env.example .env                                 # fill in secrets
cp ../server/config/users.example.json users.json    # demo users: <user>-2026
(cd ../server && dart run bin/hash_password.dart)    # hash for real users
docker compose up -d
```

Put a TLS reverse proxy in front (the app needs `https://` for the backend and `wss://` for LiveKit; open UDP 50000–50200 and TCP 7881 for media). Then build the app against it:

```sh
flutter run --dart-define=BACKEND_URL=https://ptt.example.cz/api
```

API: `POST /auth/login`, `POST /ptt/<group>/join`, `POST /admin/groups/<group>/rotate-key` (commander), `GET /health`. Backend tests: `cd server && dart test`.

## Code Layout

- `lib/main.dart` – entry point and map tile cache setup.
- `lib/app.dart` – `MaterialApp`, home screen shell (layout, navigation, logout confirmation).
- `lib/controllers/tactical_controller.dart` – `ChangeNotifier` owning session, nodes, messages, GPS, Meshtastic and PTT services.
- `lib/models/` – mesh node, messaging, navigation/waypoint models and `geo.dart` (distance, bearing, MGRS).
- `lib/screens/` – login, map, team, messages, systems pages.
- `lib/widgets/` – shared, node, position and navigation widgets.
- `lib/controllers/ptt_controller.dart` – PTT state and floor control over a `VoiceTransport` (LiveKit in `lib/services/ptt/`).
- `lib/services/` – BLE, protobuf, auth/backend client, location, storage and offline tile services.
- `server/` – backend; `deploy/` – docker-compose with LiveKit.

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
