# Changelog

## Unreleased

- Own base point: marked in the point editor, shown with a house and
  offered first in the car-mode target list.
- In-app help in Czech (System → Nápověda), searchable.
- Navigate to / message a member from the team list; message actions
  (show a position on the map, direct reply, navigate, copy).

## 1.2.0 (build 3) – 2026-10-24

- Lost contact alerts with navigation to the last known position.
- Message search (case and diacritics ignored) and a priority filter.
- Car mode: own status, quick messages and navigation target picked from
  large buttons.
- Mission log for the after-action review, shown in System and exported
  as CSV.
- Point age in the list, faded old points on the map and a clean-up of
  received points older than 6 h.
- ETA from the own speed instead of a fixed walking pace; low battery
  warnings for the own and teammates' T-Beams.
- Layout fixes for the team phone found by screen-by-screen audits
  (Messages in landscape, map cards and buttons, forms with the keyboard,
  navigation rail).
- Internal: the mission log and unread counts live in their own classes;
  layout and keyboard audits run in the test suite.

## 1.1.0 (build 2) – 2026-10-24

### Navigation and map
- Navigate to a chosen target: a teammate (follows them), a mission point
  or any tapped position. Dashed line on the map; car mode and Android
  Auto show it first; ends on arrival (50 m), deletion or with ✕.
- Enter coordinates by hand: full or short MGRS (zone and square from the
  own position) or decimal degrees. Typed MGRS resolves to the centre of
  its square, so it reads back with the same digits.
- Ruler: distance and azimuth of each segment and the total path.
- Heading-up map driven by the GPS course (kept while stopped); the own
  arrow always shows the course.
- Teammates' trails over the last 30 minutes.
- Warning within 300 m of a DANGER point (bar + vibration, once per
  approach; clears beyond 450 m).

### Team and messages
- Member status (OK, V POHYBU, NA POZICI, ZRANĚN, POTŘEBUJI PODPORU,
  MIMO AKCI) sent as `STAV | <callsign> | <status>`; urgent ones raise an
  alert with "Navigovat" and "Beru".
- Unread message counts on the Messages tab and per group.
- Editable one-tap quick messages.
- Mission points can be edited (type, note) and re-sent.
- Nodes not heard for 24 h are hidden and no longer saved; the team list
  is ordered by link status, then distance.

### Display and power
- Full screen: Android system bars hidden (swipe from the edge shows them).
- Automatic night mode from civil dusk to dawn at the own position.
- Battery saver: coarser GPS and sparser position sharing.
- The company name wraps instead of being cut off on narrow app bars.

### Internal
- `TacticalController` split: mission trail, SOS, session refresh, danger
  proximity, peer trails, member status board and user preferences live
  in their own classes.

## 1.0.0 (build 1)

First field version: Meshtastic T-Beam over BLE (messages, positions,
waypoints, telemetry, delivery ACKs), GPS with MGRS, map with offline
packs and MGRS grid, push-to-talk over a self-hosted LiveKit server with
end-to-end encryption, internet fallback for messages and positions, SOS,
CONTACT/MEDEVAC/SITREP reports, car mode, Android Auto, background PTT,
night mode, emergency wipe, mission export (GPX + CSV) and the Dart
backend with team and group administration.
