import SwiftUI

struct StuntsView: View {
    @Environment(AppModel.self) private var model
    var openCockpit: () -> Void
    var openLab: () -> Void
    @State private var notArmedStunt: Stunt?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 14)]

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        statusBanner

                        GlassGroup(spacing: 14) {
                            VStack(spacing: 14) {
                                NavigationLink {
                                    SystemCheckView(openLab: openLab)
                                } label: {
                                    featureRow(symbol: "checklist", title: "Systemcheck",
                                               text: "Ruder & Motor testen – prüft, ob das Protokoll passt.", tint: Theme.accent)
                                }
                                NavigationLink {
                                    FlightSchoolView()
                                } label: {
                                    featureRow(symbol: "graduationcap.fill", title: "Flugschule",
                                               text: "Checkliste, Start, Kurven, Landung & Laden.", tint: .blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Text("Stunts")
                            .font(.title2.bold())
                            .fontDesign(.rounded)
                            .padding(.top, 4)

                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(Stunt.all) { stunt in
                                StuntCard(stunt: stunt, isRunning: model.flight.stunt?.stunt.id == stunt.id) {
                                    if model.flight.isArmed {
                                        model.flight.run(stunt)
                                        openCockpit()
                                    } else {
                                        notArmedStunt = stunt
                                    }
                                }
                            }
                        }

                        Label("Stunts werden vom Handy gesteuert: Motor & Ruder folgen einer Sequenz. Mit STOP oder „Abbrechen“ übernimmst du sofort wieder.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Stunts & Schule")
            .alert(item: $notArmedStunt) { stunt in
                Alert(
                    title: Text("\(stunt.name): Motor gesichert"),
                    message: Text("Stunts laufen nur im Flug. Verbinde das Flugzeug, schalte im Cockpit den Motor scharf und starte dann den Stunt."),
                    primaryButton: .default(Text("Zum Cockpit"), action: openCockpit),
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var statusBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: model.flight.isArmed ? "bolt.fill" : (model.link.isReady ? "checkmark.circle.fill" : "airplane.circle"))
                .font(.title)
                .foregroundStyle(model.flight.isArmed ? Theme.warning : (model.link.isReady ? Theme.accent : .secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(model.flight.isArmed ? "Motor scharf – bereit für Stunts" : (model.link.isReady ? "Verbunden mit \(model.link.name)" : "Kein Flugzeug verbunden"))
                    .font(.headline)
                Text(model.link.isReady ? "Akku \(model.link.batteryPercent.map { "\($0) %" } ?? "–")" : "Verbinde dein SmartPlane im Cockpit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private func featureRow(symbol: String, title: String, text: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .card(padding: 14)
        .contentShape(Rectangle())
    }
}

struct StuntCard: View {
    let stunt: Stunt
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: stunt.symbol)
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.bounce, value: isRunning)
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(index < stunt.difficulty ? Theme.warning : Color.secondary.opacity(0.25))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                Text(stunt.name).font(.headline)
                Text(stunt.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                HStack {
                    Label(String(format: "%.1f s", stunt.duration), systemImage: "timer")
                    Spacer()
                    if isRunning { ProgressView().controlSize(.small) }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassPanel(cornerRadius: 24, tint: isRunning ? Theme.accent.opacity(0.6) : nil, interactive: true)
        .contextMenu {
            Text(stunt.tip)
        }
    }
}

struct FlightSchoolView: View {
    private struct Lesson: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let points: [String]
    }

    private let lessons: [Lesson] = [
        Lesson(symbol: "checklist", title: "Vor dem Start", points: [
            "Wetter prüfen: Wind unter ~15 km/h, kein Regen.",
            "Flügel, Leitwerk und Propeller auf Schäden prüfen.",
            "Ruder links/rechts testen (Systemcheck).",
            "Gasprobe: Propeller dreht sauber an.",
            "Akku-Stand prüfen – unter 30 % nicht starten.",
        ]),
        Lesson(symbol: "airplane.departure", title: "Start", points: [
            "Motor scharf schalten, Gas auf 70–80 %.",
            "Gegen den Wind stellen, Flugzeug am Rumpf halten.",
            "Leicht nach oben (ca. 10–20°) kräftig gerade aus der Hand werfen.",
            "Nach dem Start Gas etwas reduzieren, Flugzeug stabilisieren.",
        ]),
        Lesson(symbol: "arrow.triangle.turn.up.right.circle", title: "Kurven fliegen", points: [
            "Handy sanft neigen – Flight Assist gibt in Kurven automatisch etwas mehr Gas.",
            "Mit Expo werden kleine Bewegungen feiner, große bleiben voll.",
            "Zieht das Flugzeug von selbst zu einer Seite: Trimmung in den Einstellungen anpassen.",
            "Der Neigungs-Nullpunkt lässt sich im Cockpit mit „Nullen“ setzen.",
        ]),
        Lesson(symbol: "airplane.arrival", title: "Landung", points: [
            "Gegen den Wind anfliegen.",
            "Gas langsam reduzieren – oder den Stunt „Sanfte Landung“ nutzen.",
            "Kurz vor dem Boden Gas auf 0, Flugzeug ausgleiten lassen.",
            "Nach der Landung Motor sichern (Knopf tippen).",
        ]),
        Lesson(symbol: "bolt.batteryblock", title: "Laden & Pflege", points: [
            "Per USB laden – die LED blinkt während des Ladens.",
            "Die App zeigt den Ladestatus (Blitz-Symbol), wenn verbunden.",
            "Ein Akku hält ca. 10–12 Minuten Flug, Laden dauert ca. 20 Minuten.",
            "Nach Abstürzen Leitwerk und Ruderanlenkung kontrollieren.",
        ]),
        Lesson(symbol: "exclamationmark.shield", title: "Sicherheit", points: [
            "Nie über Menschen, Tiere oder Straßen fliegen.",
            "Nicht in der Nähe von Flughäfen fliegen, lokale Drohnen-/Modellflugregeln beachten.",
            "STOP schaltet den Motor sofort ab, die App sichert den Motor beim Verlassen.",
        ]),
    ]

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.caption.weight(.black))
                                    .frame(width: 26, height: 26)
                                    .background(Theme.accent.opacity(0.25), in: Circle())
                                Label(lesson.title, systemImage: lesson.symbol)
                                    .font(.headline)
                            }
                            ForEach(lesson.points, id: \.self) { point in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Theme.accent)
                                    Text(point).font(.subheadline)
                                }
                            }
                        }
                        .card()
                    }
                }
                .padding(18)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Flugschule")
    }
}
