import SwiftUI

struct LogView: View {
    @Environment(AppModel.self) private var model
    @State private var levels = Set(EventLog.Level.allCases).subtracting([.debug])
    @State private var search = ""

    private var entries: [EventLog.Entry] {
        let query = search.lowercased()
        return model.log.entries.reversed().filter { entry in
            levels.contains(entry.level) &&
                (query.isEmpty || entry.message.lowercased().contains(query) || entry.category.lowercased().contains(query))
        }
    }

    var body: some View {
        List {
            Section {
                Toggle("Steuerpakete mitschreiben (25/s)", isOn: Bindable(model.log).logControlTraffic)
            }
            Section("\(entries.count) Einträge") {
                ForEach(entries.prefix(800)) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: entry.level.symbol)
                            .foregroundStyle(color(entry.level))
                            .font(.caption)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.category).font(.caption2.weight(.bold))
                                Spacer()
                                Text(entry.date.formatted(date: .omitted, time: .standard))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.message)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle("Protokoll")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    ForEach(EventLog.Level.allCases, id: \.self) { level in
                        Toggle(level.rawValue.uppercased(), isOn: Binding(
                            get: { levels.contains(level) },
                            set: { if $0 { levels.insert(level) } else { levels.remove(level) } }
                        ))
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
                ShareLink(item: model.log.exportText()) {
                    Label("Exportieren", systemImage: "square.and.arrow.up")
                }
                Button("Leeren", systemImage: "trash") { model.log.clear() }
            }
        }
    }

    private func color(_ level: EventLog.Level) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .blue
        case .tx: return Theme.warning
        case .rx: return Theme.accent
        case .warning: return .orange
        case .error: return Theme.danger
        }
    }
}
