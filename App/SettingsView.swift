// Settings: the saved TVs (add by IP or by a network search) and, per TV, which apps get a button.
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            TvsTab().tabItem { Label("Televize", systemImage: "tv") }
            ButtonsTab().tabItem { Label("Tlačítka", systemImage: "square.grid.2x2") }
        }
        .frame(width: 600, height: 600)
    }
}

/// A TV found on the network. kind: "classic" (network debugging, port 5555), "paired" (wireless debugging,
/// already paired with this Mac) or "pairing" (showing "Pair device with pairing code" right now).
struct FoundTv: Identifiable, Hashable {
    let host: String
    let port: Int
    let kind: String
    var id: String { host }
}

struct TvsTab: View {
    @ObservedObject private var model = RemoteModel.shared
    @State private var newHost = ""
    @State private var pairHost = ""
    @State private var pairCode = ""
    @State private var codes: [String: String] = [:]
    @State private var scanning = false
    @State private var found: [FoundTv]?

    var body: some View {
        Form {
            Section("Uložené televize") {
                if model.tvs.isEmpty {
                    Text("Zatím žádná. Najdi ji v síti nebo zadej její IP adresu.").foregroundStyle(.secondary)
                }
                ForEach(model.tvs) { tv in
                    HStack(spacing: 10) {
                        Image(systemName: tv.host == model.activeHost ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(tv.host == model.activeHost ? Color.accentColor : .secondary)
                            .onTapGesture { model.select(tv.host) }
                        TextField("Název", text: Binding(get: { tv.name }, set: { model.rename(tv.host, to: $0) }))
                            .textFieldStyle(.plain).labelsHidden()
                        Text(tv.tls ? "\(tv.host):\(tv.port)" : tv.host)
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        Button(role: .destructive) { model.removeTv(tv.host) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }

            Section {
                HStack {
                    Button(action: scan) { Label("Hledat znovu", systemImage: "dot.radiowaves.left.and.right") }
                        .disabled(scanning)
                    if scanning { ProgressView().controlSize(.small) }
                }
                if let found {
                    if found.isEmpty && !scanning {
                        Text("Žádná nová televize. Je zapnutá, ve stejné síti a má zapnuté ladění (viz postup níže)?")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(found) { tv in foundRow(tv) }
                }
            } header: {
                Text("Televize v síti")
            }

            Section("Přidat podle IP adresy") {
                HStack {
                    TextField("IP adresa", text: $newHost, prompt: Text("např. 192.168.1.50")).onSubmit(add)
                    Button("Přidat", action: add).disabled(newHost.isEmpty)
                }
                HStack {
                    TextField("Párování", text: $pairHost, prompt: Text("IP:port z obrazovky párování"))
                    TextField("Kód", text: $pairCode, prompt: Text("123456")).labelsHidden().frame(width: 80)
                    Button("Spárovat") { model.pair(pairHost, code: pairCode) }
                        .disabled(pairHost.isEmpty || pairCode.count < 6)
                }
                if let message = model.message {
                    Text(message).font(.callout).foregroundStyle(.orange)
                }
            }

            Section("Jak televizi připravit") {
                Text("""
                WiFi Remote ovládá televize s Androidem a Google TV (TCL, Sony, Philips, Xiaomi, Hisense, \
                Chromecast s Google TV…) přes ladění po síti.
                1. Na televizi: Nastavení → Systém → Informace → 7× klikni na Sestavení (zapne Pro vývojáře).
                2. V Možnostech pro vývojáře zapni Ladění USB a pak jedno z:
                   • Ladění přes síť / ADB přes síť: televize se tu objeví, stačí Přidat a na televizi potvrdit \
                „Povolit ladění?“.
                   • Bezdrátové ladění (Android 11 a novější): otevři Spárovat zařízení pomocí kódu, televize \
                se tu objeví, opiš šestimístný kód a klikni Spárovat.
                """)
                .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { if found == nil { scan() } }
    }

    @ViewBuilder private func foundRow(_ tv: FoundTv) -> some View {
        HStack {
            Image(systemName: "tv")
            VStack(alignment: .leading, spacing: 1) {
                Text(tv.host).font(.system(.body, design: .monospaced))
                Text(tv.kind == "pairing" ? "Čeká na párovací kód" : tv.kind == "paired" ? "Bezdrátové ladění" : "Ladění přes síť")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if tv.kind == "pairing" {
                TextField("Kód", text: Binding(get: { codes[tv.host] ?? "" }, set: { codes[tv.host] = $0 }),
                          prompt: Text("Kód"))
                    .labelsHidden().frame(width: 80)
                Button("Spárovat") {
                    model.pair("\(tv.host):\(tv.port)", code: codes[tv.host] ?? "")
                    found?.removeAll { $0 == tv }
                }
                .disabled((codes[tv.host] ?? "").filter(\.isNumber).count != 6)
            } else {
                Button("Přidat") {
                    model.addTv(tv.kind == "paired" ? "\(tv.host):\(tv.port)" : tv.host)
                    found?.removeAll { $0 == tv }
                }
            }
        }
    }

    /// mDNS through the agent's adb, plus a sweep of the local network for port 5555 (TVs that do not announce).
    private func scan() {
        scanning = true
        Task {
            async let swept = Discovery.scan()
            async let announced = AgentClient.get("/discover", timeout: 30) as? [[String: Any]] ?? []
            var byHost: [String: FoundTv] = [:]
            for item in await announced {
                guard let host = item["host"] as? String, let port = item["port"] as? Int,
                      let kind = item["kind"] as? String else { continue }
                byHost[host] = FoundTv(host: host, port: port, kind: kind)
            }
            for host in await swept where byHost[host] == nil {
                byHost[host] = FoundTv(host: host, port: 5555, kind: "classic")
            }
            found = byHost.values
                .filter { tv in tv.kind == "pairing" || !model.tvs.contains { $0.host == tv.host } }
                .sorted { $0.host.localizedStandardCompare($1.host) == .orderedAscending }
            scanning = false
        }
    }

    private func add() {
        model.addTv(newHost)
        newHost = ""
    }
}

struct ButtonsTab: View {
    @ObservedObject private var model = RemoteModel.shared
    @State private var filter = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Televize", selection: Binding(get: { model.activeHost }, set: { model.select($0) })) {
                    ForEach(model.tvs) { Text($0.name).tag($0.host) }
                }
                .frame(maxWidth: 300)
                Spacer()
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Na ovladači").font(.headline)
                    Text("Přetažením změníš pořadí.").font(.caption).foregroundStyle(.secondary)
                    List {
                        ForEach(model.buttons) { item in
                            HStack {
                                Circle().fill(brandColor(for: item.package)).frame(width: 9, height: 9)
                                TextField("Název", text: Binding(get: { item.name }, set: { rename(item, $0) }))
                                    .textFieldStyle(.plain)
                                Spacer()
                                Button { model.setButtons(model.buttons.filter { $0 != item }) } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .onMove { from, to in
                            var items = model.buttons
                            items.move(fromOffsets: from, toOffset: to)
                            model.setButtons(items)
                        }
                    }
                    .listStyle(.bordered)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Aplikace na televizi").font(.headline)
                        Spacer()
                        if model.loadingInstalled { ProgressView().controlSize(.small) }
                        Button { model.loadInstalled() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless).help("Načíst znovu z televize")
                    }
                    TextField("Hledat", text: $filter).textFieldStyle(.roundedBorder)
                    List(available) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Button { model.setButtons(model.buttons + [item]) } label: {
                                Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .listStyle(.bordered)
                    .overlay {
                        if model.installed.isEmpty && !model.loadingInstalled {
                            Text("Televize neodpovídá. Je zapnutá?").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(20)
        .onAppear { if model.installed.isEmpty { model.loadInstalled() } }
    }

    private var available: [AppButtonItem] {
        model.installed.filter { app in
            !model.buttons.contains { $0.package == app.package }
                && (filter.isEmpty || app.name.localizedCaseInsensitiveContains(filter)
                    || app.package.localizedCaseInsensitiveContains(filter))
        }
    }

    private func rename(_ item: AppButtonItem, _ name: String) {
        model.setButtons(model.buttons.map { $0.package == item.package ? AppButtonItem(package: $0.package, name: name) : $0 })
    }
}
