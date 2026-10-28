// The keys the remote can send and readable names for common TV apps.
import Foundation

enum TvCommands {
    /// Named keys the window and the widgets may send; anything else is refused, so nothing can run
    /// arbitrary shell commands on the TV through the agent.
    static let keys: [String: String] = [
        "on": "KEYCODE_WAKEUP", "off": "KEYCODE_SLEEP", "power": "KEYCODE_POWER", "home": "KEYCODE_HOME",
        "back": "KEYCODE_BACK", "up": "KEYCODE_DPAD_UP", "down": "KEYCODE_DPAD_DOWN", "left": "KEYCODE_DPAD_LEFT",
        "right": "KEYCODE_DPAD_RIGHT", "ok": "KEYCODE_DPAD_CENTER", "volup": "KEYCODE_VOLUME_UP",
        "voldown": "KEYCODE_VOLUME_DOWN", "mute": "KEYCODE_VOLUME_MUTE", "play": "KEYCODE_MEDIA_PLAY_PAUSE",
        "rewind": "KEYCODE_MEDIA_REWIND", "forward": "KEYCODE_MEDIA_FAST_FORWARD", "chup": "KEYCODE_CHANNEL_UP",
        "chdown": "KEYCODE_CHANNEL_DOWN", "input": "KEYCODE_TV_INPUT", "settings": "KEYCODE_SETTINGS",
        "menu": "KEYCODE_MENU", "search": "KEYCODE_SEARCH",
    ]

    static func isPackage(_ s: String) -> Bool {
        s.range(of: #"^[A-Za-z][\w.]*$"#, options: .regularExpression) != nil
    }

    static func isHost(_ s: String) -> Bool {
        s.range(of: #"^[\w.-]+(:\d{1,5})?$"#, options: .regularExpression) != nil
    }

    static let names: [String: String] = [
        "net.cme.voyo.cz.tvapp": "Oneplay", "com.netflix.ninja": "Netflix",
        "com.google.android.youtube.tv": "YouTube", "com.google.android.youtube.tvkids": "YouTube Kids",
        "com.google.android.youtube.tvmusic": "YouTube Music", "org.xbmc.kodi": "Kodi",
        "com.skyshowtime.skyshowtime.google": "SkyShowtime", "tv.poda.tv": "Poda", "com.spotify.tv.android": "Spotify",
        "com.amazon.amazonvideo.livingroom": "Prime Video", "com.disney.disneyplus": "Disney+",
        "com.hbo.hbonow": "HBO Max", "com.wbd.stream": "HBO Max", "com.apple.atve.androidtv.appletv": "Apple TV",
        "com.plexapp.android": "Plex", "org.jellyfin.androidtv": "Jellyfin", "com.google.android.tv": "Live TV",
        "com.android.vending": "Google Play", "com.android.tv.settings": "Settings",
        "cz.ceskatelevize.ivysilani": "iVysílání", "cz.prima.iprima.tv": "Prima+", "cz.prima.tvapp": "Prima+",
        "com.stremio.one": "Stremio", "com.twitch.android.app": "Twitch", "com.google.android.videos": "Google TV",
        "com.android.chrome": "Chrome", "tv.pluto.android": "Pluto TV", "com.iqiyi.i18n.tv": "iQIYI",
        "com.gathin.tvhome": "CleanYourTV", "com.tcl.tv": "Live TV", "com.internet.tvbrowser": "Browser",
        "com.tcl.ui_mediaCenter": "Media Center", "com.tcl.t_solo": "T-Solo", "com.tcl.gallery": "Gallery",
        "com.sony.dtv.tvx": "Live TV", "org.videolan.vlc": "VLC", "com.mxtech.videoplayer.ad": "MX Player",
        "com.teamsmart.videomanager.tv": "SmartTube", "com.peacocktv.peacockandroid": "Peacock",
        "com.cbs.ott": "Paramount+", "com.crunchyroll.crunchyroid": "Crunchyroll", "com.dazn": "DAZN",
    ]

    static func name(for package: String) -> String {
        if let name = names[package] { return name }
        let skip: Set<String> = ["com", "tv", "android", "app", "google", "androidtv", "atv"]
        let parts = package.split(separator: ".").map(String.init).filter { !skip.contains($0) }
        return (parts.last ?? package).replacingOccurrences(of: "_", with: " ").capitalized
    }
}
