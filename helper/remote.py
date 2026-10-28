#!/usr/bin/env python3
"""ADB helper for the WiFi Remote Mac app: keeps one connection to an Android / Google TV and
answers one JSON line per command line on stdin. No network port is opened; only the app (its login agent)
that started it can talk to it. Works with any Android TV that has network debugging on.

Commands:
    host <ip>      switch to another TV (the next command connects to it)
    key <name>     a named key from KEYS (power, D-pad, volume, ...)
    app <package>  wake the TV and open that app
    state          {"awake": true|false}
    info           {"model": ..., "manufacturer": ...}
    installed      [[package, name], ...] the TV's launchable apps

Usage: TV_HOST=192.168.1.50 helper/remote.py   (then type commands, e.g. "key home")
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tv  # noqa: E402  (reads TV_HOST and exits with a hint when it is missing)

# Named keys the app may send; anything else is refused, so the helper never runs arbitrary shell.
KEYS = {
    "on": "KEYCODE_WAKEUP", "off": "KEYCODE_SLEEP", "power": "KEYCODE_POWER", "home": "KEYCODE_HOME",
    "back": "KEYCODE_BACK", "up": "KEYCODE_DPAD_UP", "down": "KEYCODE_DPAD_DOWN", "left": "KEYCODE_DPAD_LEFT",
    "right": "KEYCODE_DPAD_RIGHT", "ok": "KEYCODE_DPAD_CENTER", "volup": "KEYCODE_VOLUME_UP",
    "voldown": "KEYCODE_VOLUME_DOWN", "mute": "KEYCODE_VOLUME_MUTE", "play": "KEYCODE_MEDIA_PLAY_PAUSE",
    "rewind": "KEYCODE_MEDIA_REWIND", "forward": "KEYCODE_MEDIA_FAST_FORWARD", "chup": "KEYCODE_CHANNEL_UP",
    "chdown": "KEYCODE_CHANNEL_DOWN", "input": "KEYCODE_TV_INPUT", "settings": "KEYCODE_SETTINGS",
    "menu": "KEYCODE_MENU", "search": "KEYCODE_SEARCH",
}
# Readable names for common TV apps; any other package shows a name made from its package.
NAMES = {
    "net.cme.voyo.cz.tvapp": "Oneplay", "com.netflix.ninja": "Netflix",
    "com.google.android.youtube.tv": "YouTube", "com.google.android.youtube.tvkids": "YouTube Kids",
    "com.google.android.youtube.tvmusic": "YouTube Music", "org.xbmc.kodi": "Kodi",
    "com.skyshowtime.skyshowtime.google": "SkyShowtime", "tv.poda.tv": "Poda", "com.spotify.tv.android": "Spotify",
    "com.amazon.amazonvideo.livingroom": "Prime Video", "com.disney.disneyplus": "Disney+",
    "com.hbo.hbonow": "HBO Max", "com.wbd.stream": "HBO Max", "com.apple.atve.androidtv.appletv": "Apple TV",
    "com.plexapp.android": "Plex", "org.jellyfin.androidtv": "Jellyfin", "com.google.android.tv": "Live TV",
    "com.android.vending": "Google Play", "com.android.tv.settings": "Settings", "cz.ceskatelevize.ivysilani": "iVysílání",
    "cz.prima.iprima.tv": "Prima+", "com.stremio.one": "Stremio", "com.twitch.android.app": "Twitch",
    "com.google.android.videos": "Google TV", "com.android.chrome": "Chrome", "tv.pluto.android": "Pluto TV",
    "cz.prima.tvapp": "Prima+", "com.iqiyi.i18n.tv": "iQIYI", "com.gathin.tvhome": "CleanYourTV",
    "com.tcl.tv": "Live TV", "com.internet.tvbrowser": "Browser", "com.tcl.ui_mediaCenter": "Media Center",
    "com.tcl.t_solo": "T-Solo", "com.tcl.gallery": "Gallery", "com.sony.dtv.tvx": "Live TV",
    "org.videolan.vlc": "VLC", "com.mxtech.videoplayer.ad": "MX Player", "com.teamsmart.videomanager.tv": "SmartTube",
}
PACKAGE = re.compile(r"^[A-Za-z][\w.]*$")
HOST = re.compile(r"^[\w.:-]+$")


def pretty(package):
    if package in NAMES:
        return NAMES[package]
    parts = [p for p in package.split(".") if p not in ("com", "tv", "android", "app", "google", "androidtv", "atv")]
    return (parts[-1] if parts else package).replace("_", " ").title()


class Tv:
    """One ADB connection, reopened when the TV drops it (standby, Wi-Fi blip)."""

    def __init__(self):
        self.dev = None

    def switch(self, host):
        self.close()
        tv.HOST = host

    def close(self):
        try:
            if self.dev is not None:
                self.dev.close()
        except Exception:
            pass
        self.dev = None

    def shell(self, cmd):
        for attempt in (1, 2):
            try:
                if self.dev is None:
                    # A TV seen for the first time asks "Allow USB debugging?": leave time to answer it.
                    self.dev = tv.connect(timeout=30)
                return self.dev.shell(cmd, read_timeout_s=20.0)
            except Exception:
                self.close()
                if attempt == 2:
                    raise


def installed(conn):
    out = conn.shell("cmd package query-activities --brief -a android.intent.action.MAIN "
                     "-c android.intent.category.LEANBACK_LAUNCHER")
    pkgs = []
    for line in out.splitlines():
        line = line.strip()
        if "/" in line:
            pkg = line.split("/")[0]
            if PACKAGE.match(pkg) and pkg not in pkgs:
                pkgs.append(pkg)
    return sorted(([p, pretty(p)] for p in pkgs), key=lambda a: a[1].lower())


def handle(conn, line):
    cmd, _, arg = line.partition(" ")
    if cmd == "host" and HOST.match(arg):
        conn.switch(arg)
        return {"ok": True}
    if cmd == "state":
        return {"awake": "Awake" in conn.shell("dumpsys power | grep mWakefulness=")}
    if cmd == "info":
        out = conn.shell("getprop ro.product.manufacturer; getprop ro.product.model").splitlines()
        return {"manufacturer": out[0].strip() if out else "", "model": out[1].strip() if len(out) > 1 else ""}
    if cmd == "installed":
        return installed(conn)
    if cmd == "key" and arg in KEYS:
        conn.shell(f"input keyevent {KEYS[arg]}")
        return {"ok": True}
    if cmd == "app" and PACKAGE.match(arg):
        # Wake first, so an app button also turns the TV on. Apps without a TV entry use the phone one.
        conn.shell(f"input keyevent KEYCODE_WAKEUP; "
                   f"monkey -p {arg} -c android.intent.category.LEANBACK_LAUNCHER 1 >/dev/null 2>&1 || "
                   f"monkey -p {arg} -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1")
        return {"ok": True}
    return {"error": "unknown command"}


def main():
    conn = Tv()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            reply = handle(conn, line)
        except Exception as e:
            reply = {"error": str(e) or type(e).__name__}
        print(json.dumps(reply), flush=True)


if __name__ == "__main__":
    main()
