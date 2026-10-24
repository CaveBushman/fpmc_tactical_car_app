# Tactical Mesh

Flutter hybrid prototype for a tactical Android/iOS app with Meshtastic position sharing, encrypted internet PTT voice, real map display, and future Android Auto / CarPlay support.

[![Flutter CI](https://github.com/CaveBushman/fpmc_tactical_car_app/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/CaveBushman/fpmc_tactical_car_app/actions/workflows/flutter-ci.yml)

## Current Prototype

- Ranger Green dark tactical UI.
- Real OpenStreetMap raster map with local Flutter map tile cache.
- True MGRS/UTM grid overlay (1 km / 10 km / 100 km by zoom, principal-digit labels; switchable). Tap the map for the point's MGRS, coordinates and azimuth/distance from you, then save it as a waypoint or send it to the group.
- Team map with live GPS own position (follow mode + recenter), demo baseline nodes, Meshtastic packet updates, links and range circles.
- Own position panel with fully readable MGRS fields, latitude, longitude, altitude.
- Local and UTC clock.
- Team list with distance, bearing, battery, and last seen status that ages to STALE/LOST.
- Message delivery status (sent / delivered / failed) with resend for messages the T-Beam did not take.
- Internet fallback through the group's PTT room (E2EE data channel): own position is shared every 30 s / 25 m and merged with LoRa nodes (cloud icon for internet-only members); without a connected T-Beam, group messages go over the room instead of failing. Direct messages and other groups still need the radio.
- Message view with Meshtastic group messages, direct messages, quick actions, and internet PTT system messages.
- Quick `NA POZICI` message includes full MGRS, latitude, and longitude.
- SOS mode: after confirmation a distress call with MGRS and coordinates is repeated every minute (LoRa or internet fallback) until cancelled; teammates get a red banner with vibration, an SOS point on the map and a "Beru" acknowledgement; cancelling removes it everywhere. Plain-text format, readable in other Meshtastic apps.
- Phone GPS is broadcast into the mesh (POSITION_APP, max once a minute / 50 m), so teammates see you even without a T-Beam GPS fix.
- Hold-to-talk PTT over a self-hosted LiveKit server with end-to-end encrypted audio, half-duplex floor control (one speaker at a time, "MLUVÍ …" / "OBSAZENO") and per-group rooms. Without `BACKEND_URL` the app runs in demo mode with local accounts and silent PTT.
- System screen with Meshtastic BLE, PTT server, and car mode status.
- PTT keeps working with the screen off: Android foreground service (microphone type) with a notification PTT button, iOS background audio.
- Hardware PTT: Bluetooth headset button toggles talking (also in background, Android); optional volume-down hold-to-talk while the app is open.
- Mission record: the own trail is drawn on the map (point every 15 m / minute, max 5000, stored encrypted); System → Mise exports GPX (mission waypoints + trail) and a CSV message log via the share sheet.
- Long operations: backend sessions are refreshed automatically; a revoked or expired session returns to login without wiping data (the same user gets it back). Messages that could not be sent are resent automatically once the T-Beam or the group room is back.
- Night mode (System → Nastavení, or the moon in car mode): the whole app, map included, is rendered in dimmed red to keep night vision; colours of status badges are then distinguished only by brightness and their labels.
- Full screen (System → Nastavení, default on): the Android status and navigation bars are hidden (immersive sticky); a swipe from the screen edge shows them for a moment.
- Battery saver (System → Nastavení): coarser GPS (50 m filter) and sparser position sharing — mesh every 5 min or 250 m, internet every 2 min or 100 m. SOS calls and forced updates (handshake, new room) are not throttled.
- Team hygiene: nodes not heard for 24 h disappear from the map, team list and car mode and are no longer saved; the team list is ordered self, OK, STALE, LOST, nearest first.
- Unread messages: the Messages tab and each group chip show a red count of incoming messages not yet seen; a group counts as read while it is selected on the Messages tab with the app in front.
- Danger warnings (System → Nastavení, default on): within 300 m of a DANGER point a red bar shows distance and azimuth and the phone vibrates once per approach; it clears beyond 450 m. "Beru" hides it until the next approach. SOS points are skipped.
- Navigation target: the navigation button on a target card, or "Navigovat sem" on a tapped map point, locks navigation to that teammate, point or position. The map draws a dashed amber line to it, the peek row, car mode and Android Auto show it instead of the nearest target, and it ends on arrival (50 m), when the point is deleted or with the ✕ button.
- Coordinate entry: the pin button above the recenter button takes full MGRS, MGRS without the zone ("VR 58335 40478") or without zone and square ("58335 40478", taken from your own position), or decimal degrees. The map jumps there and opens the point card (save, send, navigate). Typed MGRS resolves to the centre of its square, so it reads back with the same digits.
- Editing points: the pencil on a mission point changes its type and note; the code and position stay, so re-sending it replaces the point on teammates' maps.
- Team trails: each teammate's positions over the last 30 minutes (a point per 10 m of movement, LoRa and internet alike) are drawn as faint dotted blue lines on the map and in car mode.
- Ruler: the ruler button on the map switches taps to adding points; the panel shows the last segment (distance, azimuth) and the total. "Od mé pozice" starts at your position, "Zpět" removes the last point.
- Heading up: the compass button (top right of the map, also in car mode) turns the map so the direction of travel points up while it follows your position; the GPS course is used above 1.5 m/s and kept while stopped. The own arrow always shows the course. Panning the map returns it to north up until you recenter.
- Quick messages: one-tap templates above the reports on the Messages tab, sent to the selected group. Edit them in System → Nastavení → Rychlé zprávy (one per line; empty restores the defaults).
- Member status: pick your own status on the Team tab (OK, V POHYBU, NA POZICI, ZRANĚN, POTŘEBUJI PODPORU, MIMO AKCI). It is sent to the selected group as `STAV | <callsign> | <status>` (ZRANĚN and POTŘEBUJI PODPORU as priority) and shown with its age on team cards and, when not OK, under the member's map marker.
- Urgent status alerts: a teammate reporting ZRANĚN or POTŘEBUJI PODPORU raises a red bar (and a vibration) like an SOS call, with "Navigovat" to their position and "Beru" to dismiss it until they report again; it lapses after 30 minutes or when they report another status.
- Lost contact alerts (System → Nastavení, default on): when a teammate heard during this session goes LOST (15 min silent), a bar with a vibration offers "Navigovat" to their last position and "Beru"; it clears when they are heard again.
- Message search: the field above the message list finds text, sender or recipient, ignoring case and diacritics ("zranen" finds "ZRANĚN"); "Prioritní" shows priority messages only.
- Car mode pickers: the status button in the car-mode header, "ZPRÁVA" (OK plus your quick messages) and a tap on the target row (choose what to navigate to) open sheets of large buttons that are easy to hit while driving.
- Mission log: SOS (own and received, cancellations, answers), member statuses, lost contact, approaches to DANGER points, navigation started and reached, and points added, received or deleted are logged with their time. System → Mise shows the latest and the whole log; it is saved (encrypted) with the rest of the state and exported as `udalosti-*.csv` next to the GPX and the message CSV.
- Automatic night mode (System → Nastavení): night mode from the end of civil dusk to civil dawn at your position, computed offline. Switching night mode by hand turns the automatic mode off.
- Car mode screen (car icon in the app bar): map, nearest target, last message, OK / NA POZICI / SOS and a large hold-to-talk button; keeps the display on.
- Android Auto: POI screen with the nearest team members and mission points on the car map (tap to navigate), and incoming team messages as car-readable notifications with voice reply.
- Adaptive portrait and landscape layouts.
- Font size slider in system settings for all operational UI text except the main title; font size, last group per user and the volume-key PTT option are remembered.
- Meshtastic BLE service using the official BLE service and ToRadio/FromRadio/FromNum characteristics.
- Meshtastic packet diagnostics in system settings: packet count, decoded NodeInfo/Position/Text events, last RX time, packet size, and hex preview.
- Focused Meshtastic protobuf reader/writer for MyNodeInfo, NodeInfo, Position, TextMessage, Routing (ACK/NAK) and want_config handshake.
- Local auth service with demo roles (`operator`, `commander`, `medic`), password check (demo password `<user>-2026`, e.g. `operator-2026`), lockout after 5 failed attempts, session chip, and logout.
- Operation groups managed on the backend (name, Meshtastic channel slot 0–7, PTT on/off); the app receives them at login (demo mode: ALPHA, BRAVO, MED, COMMAND). The app reads the T-Beam's channel config and warns when a group uses a channel the radio does not have enabled.
- Backend (`server/`) issues sessions, LiveKit room tokens limited to the user's groups, and random per-group E2EE keys with commander-triggered rotation; security events go to an audit log.
- Node/message state persisted locally, AES-GCM encrypted with a key in the platform keystore, wiped on logout.
- Emergency wipe (user menu → Nouzově smazat data, hold 3 s): removes messages, positions, trail, the storage key, offline maps and settings, disconnects the T-Beam and logs out, without contacting the backend.
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

Offline packs (System → Mapy) are named areas: either the area around your position (2–25 km) or the part of the map currently on screen, zoom 10–16, max 25 000 tiles per download. Each area can be deleted separately (tiles shared with other areas stay). Tiles are kept in permanent app storage that never expires; the map reads them before the network. Bulk download is disabled for public OSM tiles ([tile usage policy](https://operations.osmfoundation.org/policies/tiles/)), so configure a provider that allows it:

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

1. CarPlay (needs Apple entitlements, see `docs/carplay.md`).
2. Replace the synthetic replay fixture with real T-Beam captures (System → Kopírovat záznam paketů).

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

Team administration: open `https://ptt.example.cz/api/admin` and log in as a commander. It manages users (create, display name, role, groups, block, new password), logs a user out everywhere, unbinds devices, rotates group keys and shows the audit log. Changes of role, groups, password or blocking end that user's sessions immediately. Users are seeded from `USERS_FILE` on first start and then kept in `DATA_DIR/users.json`.

Login protection: 5 wrong passwords lock that user name for 5 minutes from the same address only (no lock-out of others from elsewhere), and one address may try at most 30 logins per 10 minutes. Behind the TLS proxy the backend uses `X-Forwarded-For` (`TRUST_PROXY=1`, set in docker-compose); every login is audited with the client address.

Device binding: the app sends a random per-installation id at login; an account may use at most `MAX_DEVICES_PER_USER` devices (default 2, `0` = unlimited) until a commander unbinds one.

API: `POST /auth/login`, `POST /auth/refresh`, `POST /auth/password`, `POST /ptt/<group>/join`, admin endpoints under `/admin/…` (commander), `GET /health`. Backend tests: `cd server && dart test`.

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

## Release Build (Android)

Signed release builds read `android/key.properties` (git-ignored; template in `android/key.properties.example`). Without it the release build is signed with the debug key, which is fine for testing but cannot be published.

```sh
keytool -genkey -v -keystore ~/fpmc-release.jks -keyalg RSA -keysize 4096 -validity 10000 -alias fpmc
cp android/key.properties.example android/key.properties   # fill in paths and passwords
flutter build appbundle --release --dart-define=BACKEND_URL=https://ptt.example.cz/api
```

Keep the keystore and its passwords outside the repository; losing them means the app can no longer be updated on Google Play.

## Meshtastic Protocol

The app decodes/encodes Meshtastic frames with its own small protobuf reader/writer (only the fields it uses). The official Meshtastic `.proto` files are GPL-3.0, so no code generated from them is part of the app or this repository. Instead `tool/check_meshtastic_schema.sh [tag]` fetches protoc and the `.proto` files into a temporary directory and checks that every field number, wire type and port number we use matches the official schema (also a CI job). Run it when updating to a new Meshtastic firmware/protobuf release.

To capture a real session for tests: System → Meshtastic → *Kopírovat záznam paketů*, save it under `test/fixtures/` and replay it with `ReplayRadio` (see `test/replay_integration_test.dart`).

## Verify

```sh
flutter analyze
flutter test
flutter build web --release
```
