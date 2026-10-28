<p align="center">
  <img src="docs/remote.png" alt="WiFi Remote window" width="300">
</p>

<h1 align="center">WiFi Remote</h1>

<p align="center">
  A native macOS remote for Android TV and Google TV, over your Wi-Fi.<br>
  Liquid Glass design, desktop widgets, and no app to install on the TV.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26%2B-black?logo=apple" alt="macOS 26+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI%20%2B%20WidgetKit-orange?logo=swift" alt="SwiftUI and WidgetKit">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License">
</p>

---

## Features

- **Power on and off**, Home, Back, D-pad with OK, play/pause, volume, mute, input, settings and channel keys.
- **App buttons you choose.** Pick any app installed on the TV, reorder them by dragging, rename them. Each
  button wakes the TV and opens the app.
- **Several TVs.** Save as many TVs as you like, switch between them from the title, or find them with a
  network search.
- **Two desktop widgets**, each in small, medium and large sizes, working while the app window is closed:
  - *TV Remote*: power, Home, D-pad, volume, playback, input, settings and channel keys.
  - *TV Apps*: your app buttons (4, 8 or 14 of them depending on the size).
- **Keyboard control** while the window is in front: arrow keys, Return (OK), Esc (Back), H (Home),
  Space (play/pause).
- **Live status**: on, standby or unreachable.

## Supported TVs

Any TV or streaming box running **Android TV or Google TV** with network debugging (ADB over Wi-Fi): TCL,
Sony, Philips, Xiaomi, Hisense (Android models), Sharp, Chromecast with Google TV, Nvidia Shield and others.

Samsung (Tizen) and LG (webOS) TVs use different protocols and are not supported.

## Requirements

- macOS 26 or later on Apple silicon
- Xcode 26 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- An *Apple Development* signing certificate (a free Apple account in Xcode is enough). macOS only loads
  widgets from a signed extension.
- Python 3.10 or later (the build creates its own virtual environment)

## Install

```sh
git clone https://github.com/Rarach28/wifiRemote.git
cd wifiRemote
./build.sh
```

The script builds `WiFiRemote.app`, signs it with your certificate and copies it to `~/Applications`.
`TV_HOST=192.168.1.50 ./build.sh` also puts that TV in the list on first launch.

The app runs the helper from the cloned folder, so keep the repository where it is, or run `./build.sh`
again after moving it.

## Set up the TV

1. On the TV, open **Settings → System → About** and press **Build** seven times to unlock
   *Developer options*.
2. In **Developer options**, turn on **USB debugging** and **Network debugging** (on some TVs it is called
   *ADB over network*).
3. In WiFi Remote, open **Settings → TVs** and add the TV by its IP address, or press **Search network**.
4. The TV asks **"Allow debugging?"**. Tick *Always allow from this computer* and confirm.

Then choose the app buttons under **Settings → Buttons**.

## Add the widget

Right-click the desktop, choose **Edit Widgets** and search for **WiFi Remote**. Drag *Ovladač TV* (the
remote) and/or *Aplikace TV* (the app buttons) onto the desktop in the size you like. Both follow the TV and
buttons selected in the app.

> The app's interface is currently in Czech.

## How it works

```
 Window ─┐
         ├── HTTP on 127.0.0.1 + token ──▶  Agent  ──▶  helper/remote.py  ──ADB over Wi-Fi──▶  TV
 Widget ─┘                                (login item)    (adb_shell)
```

- **Agent.** The app registers a small login agent (`WiFiRemote --agent`, via `SMAppService`). It keeps one
  ADB connection open, so buttons respond instantly. It listens on `127.0.0.1` only and refuses any request
  without the random token generated at build time.
- **Widgets.** Widgets run in the macOS sandbox and cannot open ADB connections themselves. Their buttons
  are App Intents that pass each key to the agent.
- **Helper.** `helper/remote.py` speaks ADB through [adb_shell](https://github.com/JeffLIrion/adb_shell).
  It accepts a fixed set of named keys and package names only, never arbitrary shell commands.
- **ADB key.** The key the TV trusts is stored in `~/Library/Application Support/WiFi Remote`. If
  `~/.android/adbkey` already exists (Android Studio or platform-tools), that one is reused.

## Security

Network debugging gives full control of the TV to anyone on the same network whose key the TV has
accepted. Only accept the prompt for your own computer, and turn network debugging off on the TV when you
no longer need the remote.

## Uninstall

1. Quit WiFi Remote. In **System Settings → General → Login Items & Extensions**, turn off **WiFi Remote**.
2. Delete `~/Applications/WiFiRemote.app`.
3. Optionally delete `~/Library/Application Support/WiFi Remote` (the ADB key).

## Project layout

| Path | Contents |
| --- | --- |
| `App/` | The app: remote window, settings, login agent, network search |
| `Widget/` | Desktop widgets and their App Intents |
| `Shared/` | Agent client used by both the app and the widgets |
| `Agent/` | launchd property list for the login agent |
| `helper/` | Python ADB helper |
| `project.yml` | XcodeGen project spec |
| `build.sh` | Build, sign and install |

## License

[MIT](LICENSE). `helper/tv.py` is adapted from [CleanYourTV](https://github.com/Gathin23/cleanyourtv)
(MIT, Copyright (c) 2026 Gathin).
