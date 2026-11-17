# Phase 1 explained (plain English)

## The one-sentence version

I built an Android app that shows live readings from sensors, such as temperature, humidity,
air pressure and battery level. It warns you when a reading goes out of range and tells you
clearly whether the data is live. To demo it anywhere, I also built a small fake sensor network
that runs on my laptop.

## The three pieces

1. **The simulator** pretends to be three sensor devices: a greenhouse, a warehouse and a server
   room. Every second, each device sends a small message with its readings. The values drift
   gently, like real sensors, and occasionally spike so there is something to alert on. I can
   also trigger a spike on demand with one command.

2. **The broker** is the post office. Devices *publish* messages to named topics, such as
   `sensors/greenhouse/telemetry`, and anyone interested *subscribes*. This is **MQTT**, the
   standard lightweight messaging protocol for IoT. Devices and the app never talk to each
   other directly; they only talk to the broker. That makes it easy to add devices.

3. **The app** subscribes to every device's topic, so a new device shows up automatically.

## How the phone talks to the laptop safely

The broker only listens on `127.0.0.1`, which means "this computer only". Nothing on the Wi-Fi or
the internet can reach it. To let the phone in, I use `adb reverse` over the USB cable. It makes
"port 1883 on the phone" forward to "port 1883 on the laptop". The phone connects to `127.0.0.1`
too, and the cable carries the traffic. No ports are opened to the network.

## What happens to each message inside the app

1. **Receive:** the MQTT gateway gets the raw text.
2. **Parse:** the parser checks the topic and the JSON. Bad messages, such as broken JSON,
   missing numbers or unknown topics, are quietly ignored and logged. They never crash the app
   and never show error text on screen.
3. **Store:** the device store keeps the last 60 readings per device, which is about one minute.
   That feeds the chart and the min / average / max numbers.
4. **Check alerts:** the alert engine compares each reading with the thresholds. It raises an
   alert **once** when a value crosses a limit, and clears it only when the value comes back
   inside with a small margin. That margin is called *hysteresis*. Without it, a temperature
   hovering at exactly 35.0 °C would set off dozens of alerts.
5. **Show:** the screens rebuild automatically because they "watch" the store (the `provider`
   package).

## Connection handling (what happens when things go wrong)

- The status bar at the top always says one of: **Connecting**, **Live**, **Reconnecting** or
  **Offline · retrying in N s**.
- If the connection drops, the app tries again right away. Then it waits longer between attempts
  (1, 2, 4, 8, then every 10 seconds) so it doesn't hammer the broker. "Retry now" skips the wait.
- While offline, the last readings stay on screen but greyed out, and the cards say
  "No connection". You never see stale data presented as live.
- Errors are translated into plain sentences, for example "Can't reach the broker at
  127.0.0.1:1883. Check that it is running and that adb reverse is active."

## Settings

Broker address, port, topic prefix, alert thresholds and theme (light/dark/system) are saved on
the phone with `shared_preferences`. Changing the broker or prefix reconnects automatically.
Changing a threshold applies to the very next reading.

## How I know it works

- **Unit tests** cover the parser (good and bad messages), the statistics, the alert logic
  (firing once, hysteresis, per device and per sensor, threshold changes) and the reconnect logic.
  The reconnect tests use a fake clock, so the backoff can be checked without waiting.
- **Widget tests** render the real dashboard with a fake broker connection. They check the
  loading, empty, error, live-update, alert-banner, offline, detail-screen and dark-theme states.
- **Smoke test** (Node) starts the real broker and simulator on a random port. It checks that
  data flows, retained online/offline status works and the spike command works. It also checks
  that the broker *refuses* to listen on a public address.
- **End-to-end test** connects the app's real MQTT code to the real broker.
- `flutter analyze` reports no issues.

## Design choices worth mentioning in an interview

- **Feature-based folders** (telemetry, alerts, connection, dashboard, settings), so each feature
  is self-contained.
- **The MQTT library sits behind an interface** (`MqttGateway`). The whole app can be tested
  without a network, and the library could be swapped later.
- **Pure logic is separated from UI.** The parser, stats and alert engine have no Flutter
  dependencies, which makes them fast and easy to test.
- **Safety is enforced in code, not just in docs.** The broker throws an error if asked to listen
  on anything except localhost.
- **Retained last will:** each simulated device tells the broker in advance, "if I disconnect
  unexpectedly, announce me as offline". The app learns about crashes as well as clean shutdowns.

## What Phase 1 deliberately does not do

No real hardware, no broker security (TLS and passwords), no database or long-term history,
no push notifications, Android only. These are natural next phases.
