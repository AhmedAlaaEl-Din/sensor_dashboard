# Phase 2 explained (plain English)

## The one-sentence version

I added accounts, history and export. Users sign in as an admin or a viewer. A small local server
records every sensor reading in a database, so the app can show the last hour, day or week. Users
can download the data as a spreadsheet file, and the phone shows a notification when a reading
goes out of range.

## What was added

1. **A backend service (the "API")** runs next to the MQTT broker. It listens to every sensor
   message and saves it in **SQLite**, a database that is just a file (`data/history.db`). It also
   answers questions from the app over HTTP: "sign me in", "give me Greenhouse for the last 24
   hours", "give me that as CSV".
2. **Sign-in and roles in the app:** a login screen, a profile page that shows your role, and
   automatic sign-out when your session runs out.
3. **A History screen** with 1 h / 24 h / 7 d buttons, a chart and min / average / max.
4. **Export CSV:** a file you can open in Excel, shared through the normal Android share menu.
5. **Notifications:** a pop-up banner from the system when an alert triggers, even if you are
   in another app.

## How login tokens work

Think of a **wristband at an event**.

1. You show your ID once at the entrance: you send your email and password to `POST /auth/login`.
2. The server checks the password against a **hash**. It never stores the password itself, only a
   scrambled fingerprint made with bcrypt, which is slow to compute on purpose so guessing is
   expensive.
3. If it matches, you get a **wristband**: a **JWT** (JSON Web Token). It is a small piece of text
   that says "this is viewer@example.com, role viewer, valid until 12:30", plus a **signature**.
   Only the server knows the secret key used to make the signature, so if anyone changes
   "viewer" to "admin", the signature no longer matches and the server rejects it.
4. For every request after that, the app shows the wristband in the `Authorization: Bearer …`
   header. The server checks the signature and the expiry time. It doesn't need to look anything
   up, so it's fast.
5. **Short-lived** (30 minutes): if a token leaks, it is useless soon after. The app knows the
   expiry time and signs you out by itself. If the server says "expired" first, the app also signs
   out and shows "Your session expired".

On the phone the token is kept in **secure storage** (Android Keystore), not in plain settings,
so other apps can't read it.

**Admin vs viewer** is written inside the token. The **server** checks it on every protected
request. A viewer who tries to change thresholds gets "403 Forbidden", even with a hacked app. The
app also greys out those fields for viewers, but that's just for convenience, not the actual
protection.

**Other protections:** after 5 wrong passwords for an account, the server says "too many attempts,
wait a few minutes" (**rate limiting**). An unknown email and a wrong password get exactly the
same answer, so nobody can find out which emails exist.

## Why history is stored on the server, not on the phone

- **The phone isn't always listening.** When the app is closed, the phone receives nothing. The
  server runs all the time next to the broker, so it records every reading, 24/7.
- **One source of truth.** Every phone sees the same history, and a new phone can see last week's
  data immediately.
- **The phone has limited storage and battery.** A week of one reading per second for three devices
  is about 1.8 million rows. That's easy for a database on a computer and wasteful on a phone.
- **Exports and permissions** are easier to control in one place.

The server keeps **7 days** and deletes older rows every hour (**retention**), so the database
doesn't grow forever.

## What bucketing is

A week of readings is about 600,000 points per device. A phone screen is about 400 pixels wide, so
drawing every point is slow and pointless.

**Bucketing** (or *downsampling*) means: cut the time range into equal slices ("buckets") and
replace all readings in a slice with their **average**.

| Range | Bucket | Points on the chart |
|-------|--------|---------------------|
| 1 hour | 1 minute | 60 |
| 24 hours | 15 minutes | 96 |
| 7 days | 1 hour | 168 |

The database does this in one query: it groups rows by `timestamp ÷ bucket size` and averages
each group. The **min / average / max** under the chart are still computed from **all** the raw
readings, so a short spike that the average smooths out still shows up in "max".

For CSV export, the 1-hour range gives every single reading ("raw"). The 24-hour and 7-day ranges
give 1-minute and 15-minute averages to keep the file a sensible size.

## Notifications and their honest limitation

When a reading crosses a threshold, the app asks Android to show a notification. It uses a channel
with **high importance**, so it appears as a banner at the top. Tapping it opens that device.

This works while the app is open, or in the background as long as Android lets it keep running.
Android can freeze or close background apps to save battery. Getting alerts **with the app fully
closed** needs a **push service** (Firebase Cloud Messaging) and a server on the internet. This
project deliberately runs **only locally**, with no cloud, so that's documented as a limitation
rather than faked.

## Local only, still

- The broker, the API and the database all run on the laptop and listen only on `127.0.0.1`.
- The phone reaches them through the USB cable using `adb reverse` for ports 1883 and 3000.
- The JWT secret key is generated randomly on first start into a file that is never committed to
  git and never printed.
- The demo accounts (`admin@example.com`, `viewer@example.com`) are fake and documented on purpose.

## How I know it works

- **API tests (Vitest + supertest, 25 tests):** sign-in required, wrong password, expired
  token, forged token and `alg: none` rejected, rate limit, viewer vs admin permissions,
  bucketing sizes and averages, CSV format and filename, retention, input validation, security
  headers, no stack traces.
- **App tests (81 + 1 skipped):** history parsing (including bad data), the sign-in flow (success,
  wrong password, server down, restore, expiry, a 401 from the server), CSV export (request,
  filename, file content, row count), widget tests for login, profile/sign-out, history
  (load, range switch, export, error, empty) and role-aware settings.
- **Scripts:** `dev-up` and `dev-down` were tested for start, a refused double start, and stopping
  only their own processes.

## Things worth mentioning in an interview

- **Defense in depth:** the UI hides admin actions, *and* the server enforces them.
- **No native build risks:** I used Node's built-in SQLite and a pure-JS bcrypt, so it installs
  cleanly on a brand-new Node version on Windows.
- **Friendly failure:** every network error becomes a plain sentence ("Can't reach the server…"),
  never a stack trace, on both the server and the app.
- **Honest limitations:** push notifications with the app closed need the cloud, and I wrote
  that down instead of pretending.
