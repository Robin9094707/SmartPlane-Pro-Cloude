import SwiftUI

/// Hardware check: moves the rudder and spins the motor briefly so the pilot can
/// confirm the protocol really controls the plane (important for the PRO variant).
struct SystemCheckView: View {
    @Environment(AppModel.self) private var model
    var openLab: () -> Void

    @State private var holdingPlane = false
    @State private var running: String?
    @State private var verdict: Bool?
    @State private var testTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(spacing: 16) {
                    protocolCard
                    rudderCard
                    motorCard
                    verdictCard
                }
                .padding(18)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Systemcheck")
        .onDisappear {
            testTask?.cancel()
            model.flight.clearTestOutput()
        }
    }

    private var protocolCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.link.isReady ? "Verbunden" : "Nicht verbunden", systemImage: model.link.isReady ? "checkmark.circle.fill" : "xmark.circle")
                .font(.headline)
                .foregroundStyle(model.link.isReady ? Theme.accent : .secondary)
            if let plane = model.link.plane {
                LabeledContent("Protokoll", value: plane.profile.name)
                LabeledContent("Erkennung", value: plane.detection)
                LabeledContent("Motor-UUID", value: plane.engine.uuid.uuidString)
                    .font(.caption.monospaced())
                LabeledContent("Ruder-UUID", value: plane.rudder.uuid.uuidString)
                    .font(.caption.monospaced())
                LabeledContent("Gesendet", value: "Motor \(model.link.sentEngine) · Ruder \(model.link.sentRudder)")
                    .monospacedDigit()
            } else {
                Text("Verbinde zuerst das Flugzeug im Cockpit.").foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var rudderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("1 · Ruder", systemImage: "arrow.left.and.right").font(.headline)
            Text("Schau auf das Seitenruder am Heck. Es sollte nach links, rechts und zurück in die Mitte fahren.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                testButton("Links", id: "left") { await pulse(throttle: 0, rudder: -1, seconds: 0.9) }
                testButton("Rechts", id: "right") { await pulse(throttle: 0, rudder: 1, seconds: 0.9) }
                testButton("Wackeln", id: "wiggle") {
                    for _ in 0..<3 {
                        await pulse(throttle: 0, rudder: -1, seconds: 0.35)
                        await pulse(throttle: 0, rudder: 1, seconds: 0.35)
                    }
                }
            }
        }
        .card()
    }

    private var motorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("2 · Motor", systemImage: "fanblades").font(.headline)
            Text("Der Propeller dreht für 1,5 s mit ca. 20 % Leistung. Flugzeug gut festhalten, Finger weg vom Propeller!")
                .font(.subheadline).foregroundStyle(.secondary)
            Toggle("Ich halte das Flugzeug fest", isOn: $holdingPlane)
            HStack(spacing: 10) {
                testButton("Motor 20 %", id: "motor", enabled: holdingPlane) {
                    await ramp(to: 0.2, seconds: 0.4)
                    await pulse(throttle: 0.2, rudder: 0, seconds: 1.1)
                    await ramp(from: 0.2, to: 0, seconds: 0.3)
                }
            }
        }
        .card()
    }

    private var verdictCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("3 · Ergebnis", systemImage: "questionmark.circle").font(.headline)
            Text("Hat sich Ruder bzw. Propeller bewegt?").font(.subheadline)
            HStack(spacing: 10) {
                Button("Ja, alles bewegt sich", systemImage: "hand.thumbsup.fill") { verdict = true }
                    .glassButtonStyle(prominent: verdict == true)
                Button("Nein", systemImage: "hand.thumbsdown") { verdict = false }
                    .glassButtonStyle(prominent: verdict == false)
            }
            if verdict == true {
                Label("Perfekt – das Protokoll passt. Viel Spaß beim Fliegen!", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.accent)
            } else if verdict == false {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mögliche Ursachen:").font(.subheadline.weight(.semibold))
                    Text("• Die PRO-Firmware nutzt andere UUIDs oder Werteformate.\n• Akku leer oder Flugzeug im Lademodus.\n• Ruder ist mechanisch blockiert.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Im Labor kannst du jede Characteristic mit dem Live-Regler testen und als Motor/Ruder zuordnen.")
                        .font(.subheadline)
                    Button("Im Labor untersuchen", systemImage: "stethoscope", action: openLab)
                        .glassButtonStyle(prominent: true)
                }
            }
        }
        .card()
    }

    private func testButton(_ title: String, id: String, enabled: Bool = true, action: @escaping () async -> Void) -> some View {
        Button {
            testTask?.cancel()
            running = id
            testTask = Task {
                await action()
                model.flight.clearTestOutput()
                running = nil
            }
        } label: {
            HStack {
                if running == id { ProgressView().controlSize(.small) }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .glassButtonStyle()
        .disabled(!model.link.isReady || !enabled || model.flight.isArmed || (running != nil && running != id))
    }

    private func pulse(throttle: Double, rudder: Double, seconds: Double) async {
        guard !Task.isCancelled else { return }
        model.flight.setTestOutput(throttle: throttle, rudder: rudder)
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func ramp(from start: Double = 0, to end: Double, seconds: Double) async {
        let steps = 10
        for step in 0...steps {
            guard !Task.isCancelled else { return }
            let value = start + (end - start) * Double(step) / Double(steps)
            model.flight.setTestOutput(throttle: value, rudder: 0)
            try? await Task.sleep(for: .seconds(seconds / Double(steps)))
        }
    }
}
