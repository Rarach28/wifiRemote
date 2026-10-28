// Settings: the saved TVs (add by IP or by a network search) and, per TV, which apps get a button.
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            TvsTab().tabItem { Label("Televize", systemImage: "tv") }
            ButtonsTab().tabItem { Label("Tlačítka", systemImage: "square.grid.2x2") }
        }
        .frame(width: 560, height: 520)
    }
}

struct TvsTab: View {
    @ObservedObject private var model = RemoteModel.shared
    @State private var newHost = ""
    @State private var scanning = false
    @State private var found: [String]?

    var body: some View {
        Form {
            Section("Uložené televize") {
                if model.tvs.isEmpty {
                    Text("Zatím žádná. Přidej ji níže.").foregroundStyle(.secondary)
                }
                ForEach(model.tvs) { tv in
                    HStack(spacing: 10) {
                        Image(systemName: tv.host == model.activeHost ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(tv.host == model.activeHost ? Color.accentColor : .secondary)
                            .onTapGesture { model.select(tv.host) }
                        TextField("Název", text: Binding(get: { tv.name }, set: { model.rename(tv.host, to: $0) }))
                            .textFieldStyle(.plain)
                        Text(tv.host).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        Button(role: .destructive) { model.removeTv(tv.host) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }

            Section("Přidat televizi") {
                HStack {
                    TextField("IP adresa, např. 192.168.1.50", text: $newHost)
                        .onSubmit(add)
                    Button("Přidat", action: add).disabled(newHost.isEmpty)
                }
                HStack {
                    Button {
                        scanning = true
                        found = nil
                        Task {
                            let hosts = await Discovery.scan()
                            found = hosts.filter { h in !model.tvs.contains { $0.host == h } }
                            scanning = false
                        }
                    } label: { Label("Hledat v síti", systemImage: "dot.radiowaves.left.and.right") }
                        .disabled(scanning)
                    if scanning { ProgressView().controlSize(.small) }
                }
                if let found {
                    if found.isEmpty {
                        Text("Nenašla se žádná další televize se zapnutým laděním přes síť.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(found, id: \.self) { host in
                        HStack {
                            Image(systemName: "tv")
                            Text(host).font(.system(.body, design: .monospaced))
                            Spacer()
                            Button("Přidat") {
                                model.addTv(host)
                                self.found?.removeAll { $0 == host }
                            }
                        }
                    }
                }
                if let message = model.message {
                    Text(message).font(.callout).foregroundStyle(.orange)
                }
            }

            Section("Jak televizi připravit") {
                Text("""
                WiFi Remote ovládá televize s Androidem a Google TV (TCL, Sony, Philips, Xiaomi, Hisense, \
                Chromecast s Google TV…) přes ADB po síti.
                1. Na televizi: Nastavení → Systém → Informace → 7× klikni na Sestavení (zapne Pro vývojáře).
                2. V Možnostech pro vývojáře zapni Ladění USB a Ladění přes síť / ADB přes síť.
                3. Přidej televizi tady. Při prvním připojení potvrď na televizi „Povolit ladění?“ \
                (zaškrtni Vždy povolit z tohoto počítače).
                """)
                .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
