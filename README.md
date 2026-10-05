# AktifDesk

[![Build](https://github.com/k516crypro/aktifdesk/actions/workflows/build.yml/badge.svg)](https://github.com/k516crypro/aktifdesk/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/k516crypro/aktifdesk)](https://github.com/k516crypro/aktifdesk/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Turn your Android phone or tablet into a low-latency game-streaming remote and controller for your Windows PC — powered by [Sunshine](https://github.com/LizardByte/Sunshine) / [Moonlight](https://moonlight-stream.org/).**

AktifDesk is a single Flutter codebase with two roles:

| Platform | Role |
|---|---|
| **Windows** (`AktifDesk.exe`) | **PC host.** Finds, starts and configures Sunshine, runs the AFK keep-awake engine, and connects to your phone after you type the phone's pairing code. Can also remote-control a phone that chose *Bu telefonu uzaktan yönet*. |
| **Android** (`AktifDesk.apk`) | **Flexible.** Pick a role on launch: manage a Windows PC (existing), act as a **phone remote host** (show a code so another device controls this phone), or **connect by code** to remote-control another phone. |

> **Status: v1.3.1 — release-signed APKs.** Same features as v1.3.0 (accessibility input, Tam erişim, Railway relay, R8). Sideload APKs use a dedicated release keystore (not Android Debug) to avoid browser/Play Protect “malware” heuristics for debug-signed packages. See [Download](#download) and [Signing (release keystore)](#signing-release-keystore).

---

## Features

### Available in v1.2.0

- **Code-only pairing — no IP addresses anywhere.**
  - The phone shows a **6-digit pairing code** (*Eşleştirme kodun*). You type it on the PC (*Eşleştirme kodunu gir* → *Eşleştir*); the PC finds the phone on the LAN by itself (UDP discovery, no mDNS dependency) and connects.
  - After the first pairing the PC remembers the phone (long-term random key) and reconnects automatically whenever both apps are open, even if the phone's IP changed.
  - Moonlight/GameStream pairing is automatic: the phone generates the **4-digit PIN** and forwards it to the PC, which submits it to Sunshine for you.
- **Phone-as-host remote mode (v1.2 → v1.3).**
  - On Android launch pick **Bu telefonu uzaktan yönet** — pairing code + LAN discovery (port 47100) as before.
  - **AccessibilityService** injects taps / swipes / Back-Home-Recents (no root). Turkish **Tam erişim** checklist guides Accessibility, battery exemption, and notifications (own-device remote; no unused overlay / MediaProjection / boot permissions).
  - Foreground service + persistent notification + wake lock for a stabler host session; MediaProjection / encoder errors are isolated (mirror still not shipped).
  - Client touchpad sends gestures over the control channel; host performs them when Accessibility is on.
  - **Uzak bağlantı**: optional cross-network path via a baked-in Railway WebSocket relay URL (`wss://…`, integrity-hashed; not editable in Settings; no Railway token in the APK). LAN remains the fast path.
  - **Screen mirroring is still scaffolded only.** Secure PIN/pattern unlock cannot be bypassed. No Device Admin wipe.
- **Sunshine host management (Windows).** Locates `sunshine.exe` (custom path → Program Files → LocalAppData → `PATH`), detects the `SunshineService` service, starts/stops it, sets Web UI credentials, and applies settings through Sunshine's REST API (or edits `sunshine.conf` safely with a `.bak` backup when the API isn't up).
- **Native Moonlight/GameStream client (pure Dart).** `serverinfo`, full PIN pairing handshake (AES-128, SHA-256, RSA-2048 signatures, MITM check), app list, launch / resume / quit. The server certificate is pinned after pairing.
- **Full-screen, hardware-decoded streaming via Moonlight.** Once paired and launched, the video session is handed to the installed Moonlight app, which provides full-screen low-latency playback, **physical keyboard + mouse passthrough** (press `W` on a Bluetooth/USB keyboard and your character moves), gamepad support and its own on-screen controls.
- **Robust AFK mode (Windows host).**
  - Holds `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED)` so the PC and display don't sleep.
  - **Every 2 minutes** sends a harmless `SendInput` (zero-distance relative mouse move and/or an `F15` key tap) to reset Windows/game idle timers.
  - Exponential back-off on errors, a "degraded" state if `SendInput` is blocked (e.g. UIPI), sleep/clock-jump resilience, and a clean release on exit.
  - Live status (last ping, next ping, error count) on **both** the PC and the phone; optionally keeps the phone screen on while AFK is active.
- **Live LAN control channel** with automatic reconnect and status push.

### Roadmap (planned, not yet complete)

These are the target experience for AktifDesk's own in-app player. Until it ships, the equivalent functions are provided by the Moonlight app that AktifDesk hands the stream to.

- **Floating side button → slide-out side menu** during a session (AFK toggle, keyboard, settings, disconnect).
- **FPS selector from 44 to 130 FPS** in the AktifDesk UI (the protocol already sends a configurable `WxHxFPS` mode; default 1080p60).
- **Custom, editable virtual controls** — drag-and-resize layouts for WASD, a full on-screen keyboard, and mouse buttons/trackpad.
- **WebRTC fallback engine** — the engine abstraction and selector exist, but the media backend is a stub and is not bundled.
- **Phone remote screen share** — MediaProjection consent + VirtualDisplay + encoder (likely WebRTC) to mirror a host phone to a client; input forwarding without root where Android allows.

---

## How it works

```
        Windows PC                                         Android phone / tablet
┌──────────────────────────────┐  UDP discovery :47101    ┌──────────────────────────────┐
│ AktifDesk.exe (host)         │ ── query (HMAC of code) ►│ AktifDesk (client)           │
│  • PcDiscovery / PhoneLink   │ ◄── reply / beacon ───── │  • PhoneAdvertiser           │
│  • PcControlAgent            │  WebSocket → phone:47100 │  • PhoneControlServer        │
│                              │ ────────────────────────►│    (code / key auth)         │
│  • AfkScheduler (FFI)        │                          │  • GameStreamClient (Dart)   │
│  • SunshineHostManager ──┐   │                          │      │ pair / applist /      │
│                          ▼   │   GameStream HTTP(S)     │      │ launch                │
│  Sunshine (REST :47990) ◄────┼──────────────────────────┼──────┘                       │
│     │                        │                          │                              │
│     └── RTSP/RTP video+audio, ENet input ───────────────┼─► Moonlight app (decode,     │
│                              │                          │   full-screen, kbd/mouse)    │
└──────────────────────────────┘                          └──────────────────────────────┘
```

1. **Windows host manages Sunshine.** AktifDesk finds and starts Sunshine, keeps its Web UI credentials, pins Sunshine's self-signed certificate on first use (loopback only), and pushes managed settings (`sunshine_name`, `port`, `upnp`, `encoder`, `origin_web_ui_allowed=pc`).
2. **Pairing & discovery (no IP entry).**
   - The phone hosts the control WebSocket on **TCP 47100** (ephemeral port if busy), listens on **UDP 47101**, and broadcasts a small beacon every 2 s. It shows a one-time **6-digit code**.
   - When you type the code on the PC, the PC sends discovery queries to the LAN broadcast addresses (plus a unicast sweep of the local /24 as a fallback for routers that drop broadcasts), each carrying `HMAC-SHA256(code, nonce)`. Only the phone showing that code answers, with its port and an HMAC proof. The code itself never travels in discovery packets.
   - The PC then connects to `ws://<phone>:<port>/aktifdesk` with the code in `X-AktifDesk-Token` and a fresh random key in `X-AktifDesk-Pair-Key`. The phone verifies the code (constant-time), stores the key, and rotates the code (codes are one-time; 5 wrong attempts also rotate it).
   - Later the PC finds the phone by its device id and reconnects with the stored key — no code needed.
   - Commands (phone → PC): `afk.set`, `afk.ping`, `status.get`, `sunshine.pin`, `sunshine.prepare`; the PC pushes `hello`, `afk.status` / `sunshine.status` updates.
3. **Android speaks Moonlight/GameStream.** The phone has its own RSA-2048 client identity and self-signed X.509 cert (stored in Android secure storage), performs the GameStream PIN pairing with Sunshine, and lists/launches apps.
4. **Video.** The media plane (RTSP/ENet/RTP + hardware decode) is delegated to the installed **Moonlight** Android app via an intent (`ShortcutTrampoline` with the PC UUID and App ID).
5. **Fallback.** A `WebRtcHostEngine` / `WebRtcClientEngine` pair is selected only if the primary engines are unavailable; in v1.1.0 the media backend is still a stub.

Code map:

| Path | What |
|---|---|
| `lib/core/afk/` | AFK scheduler + Windows `dart:ffi` backend |
| `lib/core/sunshine/` | Sunshine discovery, REST API, config file editing |
| `lib/core/gamestream/` | Pure-Dart GameStream client, pairing crypto, DER/X.509 |
| `lib/core/control/` | UDP discovery, pairing codes, control protocol (phone-hosted WebSocket, PC agent/links, phone-remote host/client) |
| `lib/core/streaming/` | Streaming engine abstraction (Sunshine/Moonlight primary, WebRTC fallback) |
| `lib/app/` | Host / client controllers, secret storage |
| `lib/ui/` | Flutter UI |

---

## Relay (Railway)

Cross-network pairing uses a tiny WebSocket room bridge in [`relay/`](relay/).

1. Deploy the `relay/` folder to [Railway](https://railway.app) (Dockerfile + `railway.toml` included). Root Directory = `relay`.
2. Public domain should match the baked host `aktifdesk-relay-production.up.railway.app` **or** rebuild the app with:
   ```bash
   flutter build apk --release \
     --dart-define=AKTIFDESK_RELAY_URL=wss://YOUR.up.railway.app/aktifdesk-relay \
     --dart-define=AKTIFDESK_RELAY_HOST_SHA256=$(printf '%s' 'YOUR.up.railway.app' | sha256sum | cut -d' ' -f1)
   ```
3. In the app enable **Ayarlar → Uzak bağlantı**. The relay URL is **not** a user setting (tamper-checked compile-time constant). Pairing still uses the 6-digit code.

**Auth:** pairing codes + short-lived session keys only. Never put `RAILWAY_TOKEN` or other deploy secrets in the APK.

## Download

Grab the latest build from **[GitHub Releases](https://github.com/k516crypro/aktifdesk/releases/latest)**:

- `AktifDesk-android.apk` — Android client (universal APK: arm64-v8a, armeabi-v7a, x86_64)
- `AktifDesk-android-arm64-v8a.apk` / `-armeabi-v7a.apk` / `-x86_64.apk` — smaller per-ABI APKs (most phones: `arm64-v8a`)
- `AktifDesk-windows-x64.zip` — Windows host (`AktifDesk.exe` + DLLs). Built by GitHub Actions (`windows-2022`). If the zip is missing from a release, build it locally — see [Building the Windows exe](#building-the-windows-exe).

> **Sideload tip:** enable **Unknown sources** / **Install unknown apps** for your browser or file manager. If Play Protect warns, choose **Install anyway** / **More details → Install anyway**. The first install from an unknown developer may still show a warning until the app is on Play Store — that is normal for sideloaded apps and is *not* the same as a debug/malware heuristic block.

---

## Setup

1. **Install Sunshine on your PC** — <https://github.com/LizardByte/Sunshine/releases> (installer or portable).
2. **Install Moonlight on your phone** ([Google Play](https://play.google.com/store/apps/details?id=com.limelight)) — used for video decoding.
3. **Pick a role on Android** (both devices on the same Wi-Fi/LAN — no addresses to type):

   **A) Manage a Windows PC** (*PC'yi yönet* — same as v1.1.0):
   1. **Android:** open AktifDesk → choose **PC'yi yönet**. The phone shows a big 6-digit code under *Eşleştirme kodun*.
   2. **Windows:** run `AktifDesk.exe`, type the code into **Eşleştirme kodunu gir**, click **Eşleştir**. The PC finds the phone and connects.
   3. **Android** confirms (*Şu an izinleri aldık…*). Tap **Devam et** for AFK + streaming controls.

   **B) Remote-control this phone** (*Bu telefonu uzaktan yönet*):
   1. On the phone you want to control, choose **Bu telefonu uzaktan yönet** — it shows a pairing code and waits.
   2. On another phone choose **Uzaktan bağlan** (or on Windows use the same code field) and enter that code.
   3. Use keep-awake / wake / launch / ping. Screen share is not available yet.

   From then on remembered peers reconnect when both apps are open. To add another PC, use *Yeni PC eşleştir* in the phone's menu; to add another phone, use *Yeni telefon eşleştir* on the PC.
4. On the phone tap **Prepare Sunshine on PC** (*PC'de Sunshine'ı hazırla*), then **Pair (automatic PIN)** (*Eşleştir (otomatik PIN)*). Pick a game or *Desktop* (*Masaüstü*) to start streaming.
5. **Firewall** (private network): the PC only makes *outgoing* connections to the phone, so the AktifDesk control channel needs no inbound rule on the PC. If Windows asks, allow AktifDesk on **private networks** so it can also hear the phone's discovery beacons (UDP 47101).
   - Sunshine (default base port 47989): **TCP 47984, 47989, 47990, 48010** and **UDP 47998–48000, 48002, 48010**

> **Pairing troubleshooting:** the phone and PC must be on the same LAN segment. Guest Wi-Fi / “AP isolation” / client isolation blocks device-to-device traffic and discovery. Keep AktifDesk open in the foreground on the phone while pairing.

> If your game runs as Administrator, Windows UIPI can block `SendInput`. Run AktifDesk as Administrator too (the sleep block keeps working either way; AFK status will show *degraded*).

---

## Build from source

Requirements: Flutter (stable, Dart ≥ 3.13), Android SDK + JDK 17 for Android, Visual Studio 2022 with **Desktop development with C++** (including the **C++ ATL** component) for Windows.

```bash
git clone https://github.com/k516crypro/aktifdesk.git aktifdesk
cd aktifdesk
flutter pub get

flutter analyze
flutter test                     # AFK scheduler, GameStream pairing, Sunshine, discovery + control channel, phone-remote, UI

flutter build apk --release      # Android  -> build/app/outputs/flutter-apk/app-release.apk
flutter build apk --release --split-per-abi   # per-ABI APKs (app-arm64-v8a-release.apk, …)
```

You can run the host UI on a non-Windows desktop for development with `--dart-define=AKTIFDESK_HOST=true` (Windows-only calls are no-ops there).

### Building the Windows exe

Flutter's Windows target needs the **MSVC** toolchain (Visual Studio). It **cannot** be cross-compiled on Linux (Wine / MinGW are not supported). Use a real Windows machine:

1. Install [Flutter stable for Windows](https://docs.flutter.dev/get-started/install/windows) and add it to `PATH`.
2. Install **Visual Studio 2022** (Community is fine) with workload **Desktop development with C++**, plus component **C++ ATL for latest v143 build tools (x86 & x64)**.
3. Clone and build (one-liner script):

```powershell
git clone https://github.com/k516crypro/aktifdesk.git aktifdesk
cd aktifdesk
powershell -ExecutionPolicy Bypass -File .\scripts\build-windows.ps1
```

Or the same steps by hand:

```powershell
flutter config --enable-windows-desktop
flutter pub get
flutter build windows --release
# Binary folder:
#   build\windows\x64\runner\Release\AktifDesk.exe
Compress-Archive -Path .\build\windows\x64\runner\Release\* `
  -DestinationPath .\AktifDesk-windows-x64.zip -Force
```

4. Attach the zip to the release (replace the tag if you publish a newer one):

```powershell
gh release upload v1.2.0 .\AktifDesk-windows-x64.zip --repo k516crypro/aktifdesk --clobber
```

`scripts/build-windows.cmd` is a double-click wrapper around the PowerShell script.

### CI note

`.github/workflows/build.yml` builds **Windows** (`windows-2022`) and **Android** (`ubuntu-latest`) on `push` to `main`, `workflow_dispatch`, and `v*` tags. On tags, a Release job attaches `AktifDesk-windows-x64.zip` and `AktifDesk-android.apk`. If Actions is unavailable, build Windows locally as above.

---

## Signing (release keystore)

Release APKs are signed with a dedicated keystore (`android/aktifdesk-release.jks`), **not** the Android Debug certificate. That removes the common browser / Play Protect “harmful app” heuristic that flags debug-signed sideloads.

**Keep the keysafe (do not lose or commit it):**

1. `android/key.properties` and `android/*.jks` / `*.keystore` are gitignored — **never commit** them or paste passwords into Issues/PRs/CI logs.
2. Back up `aktifdesk-release.jks` **and** `key.properties` offline (encrypted drive / password manager). Losing the keystore means you cannot ship updates that Android will treat as the same app (signature mismatch).
3. Local release build (with keystore present):
   ```bash
   flutter build apk --release
   flutter build apk --release --split-per-abi
   ```
4. Verify the signer is **not** `CN=Android Debug`:
   ```bash
   apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
   ```
5. To create a new keystore on a fresh machine (only if you do not already have one):
   ```bash
   keytool -genkeypair -v -keystore android/aktifdesk-release.jks -alias aktifdesk \
     -keyalg RSA -keysize 2048 -validity 10000 \
     -dname "CN=AktifDesk, OU=AktifDesk, O=Your Name, L=City, ST=State, C=TR"
   ```
   Then write `android/key.properties` with `storePassword`, `keyPassword`, `keyAlias=aktifdesk`, `storeFile=aktifdesk-release.jks`.

Without `key.properties`, Gradle falls back to debug signing (useful for CI without secrets). Prefer uploading only release-signed APKs to GitHub Releases.

---

## Security notes (v1.3)

- Release APKs are signed with a **dedicated release keystore** (see above) and use **R8 minify + resource shrink + obfuscation**. This slows casual reverse engineering; it is **not** perfect protection.
- Launcher uses **adaptive icons** from `assets/branding/aktifdesk-icon.jpg` (full-bleed brand blue, artwork inside the circular safe zone).
- AccessibilityService description states **own-device remote control** only. Unused dangerous permissions (`SYSTEM_ALERT_WINDOW`, `FOREGROUND_SERVICE_MEDIA_PROJECTION`, `RECEIVE_BOOT_COMPLETED`) were removed. Play Protect may still warn on first sideload / Accessibility enable for unknown developers until Play Store listing — that is expected.
- Relay host is integrity-checked (SHA-256 of hostname). Runtime Settings / SharedPreferences / deeplinks cannot override it (fail closed).
- Pairing keys use platform secure storage. Do not log codes/tokens.
- Public relay speaks **wss://** only (except localhost `ws://` for dev).

## Limitations & TODOs

Being honest about where v1.2.0 stands:

- **Windows-only code paths have not been tested on real hardware yet.** The `SetThreadExecutionState` / `SendInput` FFI calls and Sunshine service control (`sc`, `tasklist`, `taskkill`) are covered by unit tests with fakes. Grab `AktifDesk-windows-x64.zip` from [Releases](https://github.com/k516crypro/aktifdesk/releases/latest), or build it locally — see [Building the Windows exe](#building-the-windows-exe).
- **Anti-cheat may block virtual input.** Some games/anti-cheat systems ignore or flag `SendInput` events and virtual devices. Use at your own risk and respect each game's terms of service.
- **AFK is not guaranteed.** Games with their own server-side or input-pattern AFK detection may still kick you; the AFK engine only resets the OS/game idle timers that react to local input.
- **Video decode is handed to the installed Moonlight app.** AktifDesk does not yet render the stream itself, so the in-app player features (side menu, FPS selector, editable virtual controls) are on the roadmap.
- **WebRTC fallback is a stub** — no media backend is bundled.
- **Secrets on Windows** (phone pairing keys, Sunshine Web UI password) are stored in the user profile via SharedPreferences, not encrypted. Moving them to DPAPI is a TODO. On Android they use the Keystore-backed secure storage.
- **The control channel is plain `ws://` on the LAN.** The first connection is authenticated by the 6-digit one-time code, later ones by a 256-bit random key, but traffic is not encrypted and a 6-digit code is brute-forceable by an attacker who can sniff the LAN during pairing. Pair on a trusted network and don't expose ports 47100/47101 to the internet. TLS / a PAKE-based pairing is a TODO.
- **Discovery uses UDP broadcast + a /24 sweep**, not mDNS; networks that isolate clients (guest Wi-Fi, AP isolation) prevent pairing.
- **The phone must have AktifDesk open** for the PC (or another phone) to connect; there is no Android background service yet.
- **Phone remote is not full TeamViewer-style control.** No MediaProjection screen mirror yet (stub only). Keep-awake needs AktifDesk in the foreground. Secure lock screens (PIN/pattern/password/biometrics) cannot be unlocked remotely without Device Owner / Accessibility abuse — we only wake the screen and dismiss an *insecure* keyguard when the OS allows it. Tap/swipe injection without root is not implemented.
- The UI is currently in Turkish; English localisation is a TODO.

Contributions and bug reports are welcome via [Issues](https://github.com/k516crypro/aktifdesk/issues).

---

## License

[MIT](LICENSE) © 2026 Miraç Aytaç

AktifDesk is an independent project and is not affiliated with the Sunshine or Moonlight projects. Sunshine is licensed under GPL-3.0 and Moonlight under GPL-3.0; they are installed separately and are not bundled with AktifDesk.
