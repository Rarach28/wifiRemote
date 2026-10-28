// Desktop widgets: "TV Remote" (power, D-pad, media keys) and "TV Apps" (the app buttons chosen in the app).
// Buttons run App Intents in this sandboxed extension, which pass them to the agent on 127.0.0.1; the agent
// holds the ADB connection.
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Intents

struct TvKeyIntent: AppIntent {
    static let title: LocalizedStringResource = "TV key"
    static let isDiscoverable = false

    @Parameter(title: "Key") var key: String

    init() {}
    init(_ key: String) { self.key = key }

    func perform() async throws -> some IntentResult {
        _ = await AgentClient.get("/key/" + key)
        // Give the TV a moment to change state, so the widget redraws with the new one.
        if key == "on" || key == "off" { try? await Task.sleep(for: .seconds(2)) }
        return .result()
    }
}

struct TvAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Open TV app"
    static let isDiscoverable = false

    @Parameter(title: "Package") var package: String

    init() {}
    init(_ package: String) { self.package = package }

    func perform() async throws -> some IntentResult {
        _ = await AgentClient.get("/app/" + package)
        return .result()
    }
}

// MARK: - Timeline

struct RemoteEntry: TimelineEntry {
    let date: Date
    /// nil: the agent or the TV did not answer.
    let awake: Bool?
    let tv: String
    let apps: [(String, String)]
}

struct Provider: TimelineProvider {
    static let sample = RemoteEntry(date: .now, awake: true, tv: "TV", apps: [
        ("com.netflix.ninja", "Netflix"), ("com.google.android.youtube.tv", "YouTube"),
        ("com.spotify.tv.android", "Spotify"), ("org.xbmc.kodi", "Kodi"),
    ])

    func placeholder(in context: Context) -> RemoteEntry { Self.sample }

    func getSnapshot(in context: Context, completion: @escaping (RemoteEntry) -> Void) {
        if context.isPreview { return completion(Self.sample) }
        Task { completion(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RemoteEntry>) -> Void) {
        Task {
            let entry = await load()
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(5 * 60))))
        }
    }

    private func load() async -> RemoteEntry {
        async let state = AgentClient.get("/state", timeout: 10)
        async let buttons = AgentClient.get("/buttons", timeout: 5)
        let awake = (await state as? [String: Any])?["awake"] as? Bool
        let info = await buttons as? [String: Any]
        return RemoteEntry(date: .now, awake: awake, tv: info?["tv"] as? String ?? "",
                           apps: AgentClient.apps(info?["apps"]))
    }
}

// MARK: - Building blocks

/// A frosted key: white glass, or the given colour for power and the apps.
struct Key<Label: View>: View {
    let intent: any AppIntent
    var tint: Color? = nil
    var round = false
    @ViewBuilder let label: () -> Label

    var body: some View {
        let shape = round ? AnyShape(Circle()) : AnyShape(Capsule())
        Button(intent: intent) {
            label()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background {
            shape.fill((tint ?? .white).opacity(tint == nil ? 0.14 : 0.75))
            shape.stroke(.white.opacity(0.22), lineWidth: 0.8)
        }
    }
}

/// A round key of a fixed size with an SF Symbol.
struct SymbolKey: View {
    let symbol: String
    let key: String
    var tint: Color?
    var size: CGFloat

    init(_ symbol: String, _ key: String, tint: Color? = nil, size: CGFloat = 40) {
        self.symbol = symbol
        self.key = key
        self.tint = tint
        self.size = size
    }

    var body: some View {
        Key(intent: TvKeyIntent(key), tint: tint, round: true) {
            Image(systemName: symbol).font(.system(size: size * 0.38, weight: .semibold))
        }
        .frame(width: size, height: size)
    }
}

/// A capsule key with a short text label (input, settings, channels).
struct TextKey: View {
    let title: String
    let key: String

    var body: some View {
        Key(intent: TvKeyIntent(key)) {
            Text(title).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1)
        }
        .frame(height: 28)
    }
}

struct AppKey: View {
    let app: (String, String)

    var body: some View {
        let (r, g, b) = brandRGB(for: app.0)
        Key(intent: TvAppIntent(app.0), tint: Color(red: r, green: g, blue: b)) {
            Text(app.1).font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 6)
        }
    }
}

struct Header: View {
    let entry: RemoteEntry

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "tv").font(.system(size: 11, weight: .semibold))
            Text(entry.tv.isEmpty ? "TV" : entry.tv)
                .font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(1)
            Spacer(minLength: 4)
            Circle().fill(entry.awake == true ? .green : entry.awake == false ? .orange : .red)
                .frame(width: 6, height: 6)
            Text(entry.awake == true ? "Zapnutá" : entry.awake == false ? "Pohotovost" : "Nedostupná")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
        }
        .foregroundStyle(.white)
    }
}

/// Up, left, OK, right, down in a cross that fills a square of the given size.
struct DPad: View {
    let size: CGFloat

    var body: some View {
        let key = size / 3.2
        let gap = size * 0.03
        VStack(spacing: gap) {
            SymbolKey("chevron.up", "up", size: key)
            HStack(spacing: gap) {
                SymbolKey("chevron.left", "left", size: key)
                Key(intent: TvKeyIntent("ok"), tint: .white.opacity(0.35), round: true) {
                    Text("OK").font(.system(size: key * 0.32, weight: .bold, design: .rounded))
                }
                .frame(width: key, height: key)
                SymbolKey("chevron.right", "right", size: key)
            }
            SymbolKey("chevron.down", "down", size: key)
        }
        .frame(width: size, height: size)
    }
}

struct PowerRow: View {
    let size: CGFloat

    var body: some View {
        HStack {
            SymbolKey("power", "on", tint: .green, size: size)
            Spacer(minLength: 0)
            SymbolKey("house.fill", "home", size: size)
            Spacer(minLength: 0)
            SymbolKey("power", "off", tint: .red, size: size)
        }
    }
}

struct WidgetBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.15, green: 0.19, blue: 0.38), Color(red: 0.04, green: 0.06, blue: 0.15)],
                       startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Remote widget

struct RemoteWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RemoteEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            case .systemMedium: medium
            default: large
            }
        }
        .containerBackground(for: .widget) { WidgetBackground() }
    }

    private var small: some View {
        VStack(spacing: 0) {
            Header(entry: entry)
            Spacer(minLength: 6)
            PowerRow(size: 38)
            Spacer(minLength: 6)
            HStack {
                SymbolKey("arrow.uturn.backward", "back", size: 38)
                Spacer(minLength: 0)
                SymbolKey("playpause.fill", "play", size: 38)
                Spacer(minLength: 0)
                SymbolKey("speaker.slash.fill", "mute", size: 38)
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(spacing: 0) {
                Header(entry: entry)
                Spacer(minLength: 6)
                PowerRow(size: 38)
                Spacer(minLength: 6)
                HStack {
                    SymbolKey("arrow.uturn.backward", "back", size: 34)
                    Spacer(minLength: 0)
                    SymbolKey("speaker.minus.fill", "voldown", size: 34)
                    Spacer(minLength: 0)
                    SymbolKey("speaker.plus.fill", "volup", size: 34)
                }
            }
            DPad(size: 126)
        }
    }

    private var large: some View {
        VStack(spacing: 0) {
            Header(entry: entry)
            Spacer(minLength: 8)
            PowerRow(size: 48)
            Spacer(minLength: 8)
            HStack {
                DPad(size: 168)
                Spacer(minLength: 8)
                VStack(spacing: 10) {
                    SymbolKey("speaker.plus.fill", "volup", size: 44)
                    SymbolKey("speaker.slash.fill", "mute", size: 44)
                    SymbolKey("speaker.minus.fill", "voldown", size: 44)
                }
            }
            Spacer(minLength: 8)
            HStack {
                SymbolKey("arrow.uturn.backward", "back", size: 42)
                Spacer(minLength: 0)
                SymbolKey("backward.fill", "rewind", size: 42)
                Spacer(minLength: 0)
                SymbolKey("playpause.fill", "play", size: 42)
                Spacer(minLength: 0)
                SymbolKey("forward.fill", "forward", size: 42)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                TextKey(title: "Zdroj", key: "input")
                TextKey(title: "Nastavení", key: "settings")
                TextKey(title: "CH −", key: "chdown")
                TextKey(title: "CH +", key: "chup")
            }
        }
    }
}

// MARK: - Apps widget

struct AppsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RemoteEntry

    var body: some View {
        VStack(spacing: 8) {
            Header(entry: entry)
            if entry.apps.isEmpty {
                Spacer(minLength: 0)
                Text("Vyber aplikace v nastavení WiFi Remote.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer(minLength: 0)
            } else {
                grid
            }
        }
        .containerBackground(for: .widget) { WidgetBackground() }
    }

    /// Small: 2 × 2, medium: 4 × 2, large: 2 × 7.
    private var columns: Int { family == .systemMedium ? 4 : 2 }
    private var rows: Int { family == .systemLarge ? 7 : 2 }

    /// Rows fill the widget's height; fewer apps than slots leave the rest of the grid empty.
    private var grid: some View {
        let shown = Array(entry.apps.prefix(columns * rows))
        return VStack(spacing: 6) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<columns, id: \.self) { col in
                        let i = row * columns + col
                        if i < shown.count { AppKey(app: shown[i]) } else { Color.clear }
                    }
                }
            }
        }
    }
}

// MARK: - Widgets

struct RemoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RemoteWidget", provider: Provider()) { RemoteWidgetView(entry: $0) }
            .configurationDisplayName("Ovladač TV")
            .description("Zapnutí a vypnutí, šipky, hlasitost a přehrávání.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct AppsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AppsWidget", provider: Provider()) { AppsWidgetView(entry: $0) }
            .configurationDisplayName("Aplikace TV")
            .description("Tlačítka aplikací vybraná ve WiFi Remote. Kliknutí televizi zapne a aplikaci otevře.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct RemoteWidgets: WidgetBundle {
    var body: some Widget {
        RemoteWidget()
        AppsWidget()
    }
}
