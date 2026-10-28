// WiFi Remote: a Mac remote for Android / Google TVs, drawn in Liquid Glass, plus desktop widgets (Widget/).
// The same binary run with --agent is the login agent (Agent.swift) that holds the TV connection; the window
// and the sandboxed widgets send it their buttons.
import AppKit
import ServiceManagement
import SwiftUI
import WidgetKit

// MARK: - Model

enum TvState { case unknown, awake, asleep, offline }

@MainActor
final class RemoteModel: ObservableObject {
    static let shared = RemoteModel()

    @Published var tvs: [SavedTv] = Store.tvs
    @Published var activeHost: String = Store.activeHost
    @Published var buttons: [AppButtonItem] = []
    @Published var installed: [AppButtonItem] = []
    @Published var loadingInstalled = false
    @Published var state: TvState = .unknown
    @Published var busy = false
    @Published var message: String?
    private var timer: Timer?

    var activeTv: SavedTv? { tvs.first { $0.host == activeHost } }

    private init() {
        buttons = Store.buttons(for: activeHost)
        Task { await startAgent() }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { @MainActor in RemoteModel.shared.refresh() }
        }
    }

    /// Makes sure the login agent is registered and answering, and that it has adb.
    private func startAgent() async {
        if await AgentClient.get("/buttons", timeout: 3) == nil {
            try? SMAppService.agent(plistName: Agent.plist).register()
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(300))
                if await AgentClient.get("/buttons", timeout: 2) != nil { break }
            }
        }
        // The first launch on a Mac without adb downloads Google's Platform-Tools (about 16 MB).
        message = "Připravuji nástroje Android (adb)…"
        let ready = (await AgentClient.get("/adb", timeout: 180) as? [String: Any])?["ready"] as? Bool == true
        message = ready ? nil : "Nepodařilo se stáhnout nástroje Android (adb). Zkontroluj připojení k internetu."
        refresh()
        // A TV saved without a name yet (first run, or added while it did not answer): ask it.
        if let tv = activeTv, tv.name == "TV" || tv.name == tv.host,
           let info = await AgentClient.get("/info", timeout: 15) as? [String: String] {
            let name = [info["manufacturer"], info["model"]].compactMap { $0 }.joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { rename(tv.host, to: name) }
        }
    }

    func refresh() {
        guard !activeHost.isEmpty else { state = .offline; return }
        Task {
            let dict = await AgentClient.get("/state") as? [String: Any]
            if let awake = dict?["awake"] as? Bool { state = awake ? .awake : .asleep } else { state = .offline }
        }
    }

    private func run(_ path: String, refreshAfter: Double = 0) {
        busy = true
        Task {
            let ok = AgentClient.ok(await AgentClient.get(path))
            busy = false
            if !ok { state = .offline }
            if refreshAfter > 0 {
                try? await Task.sleep(for: .seconds(refreshAfter))
                refresh()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    func key(_ name: String) { run("/key/" + name, refreshAfter: name == "on" || name == "off" ? 2 : 0) }

    func open(_ app: AppButtonItem) { run("/app/" + app.package, refreshAfter: 2) }

    // MARK: TVs

    func select(_ host: String) {
        Store.activeHost = host
        activeHost = host
        buttons = Store.buttons(for: host)
        installed = []
        state = .unknown
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Adds a TV by its IP ("192.168.1.50", classic network debugging) or "IP:port" (wireless debugging that
    /// is already paired), connects it and names it after its model. The TV may first ask "Allow debugging?".
    func addTv(_ raw: String) {
        let input = raw.trimmingCharacters(in: .whitespaces)
        guard TvCommands.isHost(input) else {
            message = "Zadej IP adresu televize, např. 192.168.1.50."
            return
        }
        let host = String(input.split(separator: ":")[0])
        message = "Připojuji k \(host)… Pokud se na televizi objeví „Povolit ladění?“, zaškrtni Vždy povolit a potvrď."
        Task {
            // The agent saves the TV (with its port); keep asking while the TV waits for the user to allow it.
            var reply: (Int, Any?) = (0, nil)
            for _ in 0..<12 {
                reply = await AgentClient.call("/connect?host=" + input, timeout: 30)
                if reply.0 == 200 || AgentClient.error(reply.1) != "unauthorized" { break }
                try? await Task.sleep(for: .seconds(5))
            }
            tvs = Store.tvs
            guard reply.0 == 200 else {
                message = Self.explain(AgentClient.error(reply.1), host: host)
                return
            }
            select(host)
            await nameFromTv(host)
            message = nil
        }
    }

    /// Pairs a TV showing "Pair device with pairing code" (Android 11+ wireless debugging), then adds it.
    func pair(_ raw: String, code: String) {
        let input = raw.trimmingCharacters(in: .whitespaces)
        let digits = code.filter(\.isNumber)
        guard TvCommands.isHost(input), digits.count == 6 else {
            message = "Zadej IP adresu (a port) z obrazovky párování a šestimístný kód."
            return
        }
        let host = String(input.split(separator: ":")[0])
        message = "Páruji s \(host)…"
        Task {
            let reply = await AgentClient.call("/pair?host=\(input)&code=\(digits)", timeout: 60)
            tvs = Store.tvs
            guard reply.0 == 200 else {
                message = Self.explain(AgentClient.error(reply.1), host: host)
                return
            }
            select(host)
            await nameFromTv(host)
            message = nil
        }
    }

    private func nameFromTv(_ host: String) async {
        guard let info = await AgentClient.get("/info", timeout: 20) as? [String: String] else { return }
        let name = [info["manufacturer"], info["model"]].compactMap { $0 }.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if !name.isEmpty, let tv = tvs.first(where: { $0.host == host }), tv.name == host { rename(host, to: name) }
        refresh()
    }

    static func explain(_ error: String?, host: String) -> String {
        switch error {
        case "unauthorized":
            return "Televize čeká na potvrzení „Povolit ladění?“. Potvrď ho na televizi a zkus to znovu."
        case "pairing failed":
            return "Párování se nepovedlo. Zkontroluj kód a port na obrazovce párování televize."
        case "no pairing service":
            return "Televize teď nenabízí párování. Otevři na ní Bezdrátové ladění → Spárovat zařízení pomocí kódu."
        case "no debugging port":
            return "Spárováno, ale televize neohlásila port ladění. Zadej IP:port z obrazovky Bezdrátové ladění."
        case "no adb":
            return "Chybí nástroje Android (adb) a nepodařilo se je stáhnout. Zkontroluj připojení k internetu."
        case nil:
            return "Aplikace se nemůže spojit se svým agentem na pozadí. Zkus WiFi Remote znovu spustit."
        default:
            return "\(host) neodpovídá. Je televize zapnutá a má zapnuté ladění přes síť?"
        }
    }

    func rename(_ host: String, to name: String) {
        guard let i = tvs.firstIndex(where: { $0.host == host }) else { return }
        tvs[i].name = name
        Store.tvs = tvs
        WidgetCenter.shared.reloadAllTimelines()
    }

    func removeTv(_ host: String) {
        tvs.removeAll { $0.host == host }
        Store.tvs = tvs
        Store.setButtons([], for: host)
        if activeHost == host { select(tvs.first?.host ?? "") }
    }

    // MARK: App buttons

    func loadInstalled() {
        loadingInstalled = true
        Task {
            let list = await AgentClient.get("/installed", timeout: 40) as? [[String]] ?? []
            installed = list.compactMap { $0.count == 2 ? AppButtonItem(package: $0[0], name: $0[1]) : nil }
            loadingInstalled = false
        }
    }

    func setButtons(_ items: [AppButtonItem]) {
        buttons = items
        Store.setButtons(items, for: activeHost)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Remote window

func brandColor(for package: String) -> Color {
    let (r, g, b) = brandRGB(for: package)
    return Color(red: r, green: g, blue: b)
}

struct GlassKey: View {
    let symbol: String
    var label: String? = nil
    var size: CGFloat = 52
    var tintColor: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: size * 0.36, weight: .semibold))
                if let label { Text(label).font(.system(size: 10, weight: .medium)).opacity(0.8) }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .glassEffect(tintColor.map { .regular.tint($0.opacity(0.55)).interactive() } ?? .regular.interactive(),
                     in: .circle)
    }
}

/// A small capsule key for the less used buttons (input, settings, channels).
struct PillKey: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 28).contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

struct DPad: View {
    @ObservedObject var model: RemoteModel

    var body: some View {
        // The arrows are the glass view's own content, so the glass is drawn behind them, not over them.
        VStack(spacing: 6) {
            arrow("chevron.up", "up")
            HStack(spacing: 6) {
                arrow("chevron.left", "left")
                Button { model.key("ok") } label: {
                    Text("OK").font(.system(size: 17, weight: .bold, design: .rounded))
                        .frame(width: 70, height: 70).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(.white.opacity(0.12)).interactive(), in: .circle)
                arrow("chevron.right", "right")
            }
            arrow("chevron.down", "down")
        }
        .frame(width: 210, height: 210)
        .glassEffect(.regular, in: .circle)
    }

    private func arrow(_ symbol: String, _ key: String) -> some View {
        Button { model.key(key) } label: {
            Image(systemName: symbol).font(.system(size: 20, weight: .bold))
                .frame(width: 60, height: 60).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AppKey: View {
    let app: AppButtonItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(app.name)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .glassEffect(.regular.tint(brandColor(for: app.package).opacity(0.6)).interactive(), in: .capsule)
    }
}

struct StatusPill: View {
    let state: TvState
    let busy: Bool

    var body: some View {
        HStack(spacing: 6) {
            if busy { ProgressView().controlSize(.mini) } else { Circle().fill(color).frame(width: 7, height: 7) }
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
    }

    private var color: Color {
        switch state {
        case .awake: return .green
        case .asleep: return .orange
        case .offline: return .red
        case .unknown: return .gray
        }
    }

    private var text: String {
        switch state {
        case .awake: return "Zapnutá"
        case .asleep: return "Pohotovost"
        case .offline: return "Nedostupná"
        case .unknown: return "Připojuji…"
        }
    }
}

struct RemoteView: View {
    @ObservedObject private var model = RemoteModel.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            VStack(spacing: 16) {
                header.padding(.top, 6)
                if model.tvs.isEmpty {
                    empty
                } else {
                    controls
                }
            }
            .padding(22)
        }
        .frame(width: 360)
        .background(KeyCatcher(model: model))
    }

    private var header: some View {
        HStack {
            Menu {
                ForEach(model.tvs) { tv in
                    Button { model.select(tv.host) } label: {
                        if tv.host == model.activeHost { Label(tv.name, systemImage: "checkmark") } else { Text(tv.name) }
                    }
                }
                Divider()
                Button("Nastavení…") { openSettings() }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WiFi Remote").font(.system(size: 20, weight: .bold, design: .rounded))
                    HStack(spacing: 3) {
                        Text(model.activeTv?.name ?? "Žádná televize")
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
            Spacer()
            StatusPill(state: model.state, busy: model.busy)
            Button { openSettings() } label: { Image(systemName: "gearshape").font(.system(size: 14)) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "tv.badge.wifi").font(.system(size: 42)).foregroundStyle(.secondary)
            Text("Přidej televizi").font(.headline)
            Text("WiFi Remote ovládá televize s Androidem a Google TV přes Wi-Fi. V nastavení je najde v síti, nebo zadáš jejich IP adresu.")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Najít televizi") { openSettings() }.buttonStyle(.glassProminent)
        }
        .padding(.vertical, 40)
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 14) {
            GlassKey(symbol: "power", label: "Zapnout", size: 64, tintColor: .green) { model.key("on") }
            Spacer()
            GlassKey(symbol: "house.fill", label: "Domů", size: 64) { model.key("home") }
            Spacer()
            GlassKey(symbol: "power", label: "Vypnout", size: 64, tintColor: .red) { model.key("off") }
        }

        DPad(model: model)

        HStack(spacing: 14) {
            GlassKey(symbol: "arrow.uturn.backward", label: "Zpět") { model.key("back") }
            GlassKey(symbol: "playpause.fill", label: "Play") { model.key("play") }
            GlassKey(symbol: "speaker.minus.fill", label: "Tišeji") { model.key("voldown") }
            GlassKey(symbol: "speaker.slash.fill", label: "Ztlumit") { model.key("mute") }
            GlassKey(symbol: "speaker.plus.fill", label: "Hlasitěji") { model.key("volup") }
        }

        HStack(spacing: 10) {
            PillKey(title: "Zdroj") { model.key("input") }
            PillKey(title: "Nastavení") { model.key("settings") }
            PillKey(title: "CH −") { model.key("chdown") }
            PillKey(title: "CH +") { model.key("chup") }
        }

        if model.buttons.isEmpty {
            Button("Vybrat aplikace na tlačítka…") { openSettings() }
                .buttonStyle(.glass)
        } else {
            VStack(spacing: 10) {
                // Two per row; an odd last app takes the whole row.
                ForEach(Array(stride(from: 0, to: model.buttons.count, by: 2)), id: \.self) { i in
                    HStack(spacing: 10) {
                        AppKey(app: model.buttons[i]) { model.open(model.buttons[i]) }
                        if i + 1 < model.buttons.count {
                            AppKey(app: model.buttons[i + 1]) { model.open(model.buttons[i + 1]) }
                        }
                    }
                }
            }
        }

        Text("Klávesnice: šipky · Enter OK · Esc zpět · H domů · mezerník play")
            .font(.system(size: 10)).foregroundStyle(.tertiary)
    }
}

/// Keyboard: arrows, Return, Escape, H and Space work like the remote while the remote window is in front.
struct KeyCatcher: NSViewRepresentable {
    let model: RemoteModel

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak view] event in
            // Only the remote's own window: Settings needs its arrows and Return for its lists and fields.
            guard let view, NSApp.keyWindow === view.window else { return event }
            let key: String?
            switch event.keyCode {
            case 123: key = "left"
            case 124: key = "right"
            case 125: key = "down"
            case 126: key = "up"
            case 36, 76: key = "ok"
            case 53, 51: key = "back"
            case 49: key = "play"
            case 4: key = "home"
            default: key = nil
            }
            guard let key else { return event }
            Task { @MainActor in model.key(key) }
            return nil
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var monitor: Any?
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--agent") { Agent.run() }
        RemoteApp.main()
    }
}

struct RemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("WiFi Remote", id: "remote") {
            RemoteView()
                .containerBackground(.ultraThinMaterial, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}
