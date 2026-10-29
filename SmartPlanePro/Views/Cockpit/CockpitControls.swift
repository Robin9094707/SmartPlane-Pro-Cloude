import SwiftUI

/// Vertical throttle lever. Drag is relative, so touching it never makes the value jump.
struct ThrottleSlider: View {
    @Binding var value: Double
    var output: Double
    var armed: Bool
    var haptics: Bool

    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            ZStack(alignment: .bottom) {
                // Requested throttle (ghost)
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(height: height * value)
                // Actually transmitted throttle
                Rectangle()
                    .fill(LinearGradient(
                        colors: armed ? [Theme.accent, Color.yellow, Theme.warning] : [Color.gray.opacity(0.55), Color.gray.opacity(0.3)],
                        startPoint: .bottom, endPoint: .top
                    ))
                    .frame(height: height * (armed ? output : value))
                    .opacity(0.85)
                // Tick marks
                VStack(spacing: 0) {
                    ForEach((1..<10).reversed(), id: \.self) { tick in
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(.white.opacity(tick == 5 ? 0.5 : 0.22))
                            .frame(width: tick == 5 ? 26 : 14, height: 1)
                    }
                    Spacer(minLength: 0)
                }
                // Knob
                Capsule()
                    .fill(.white)
                    .frame(width: geo.size.width - 22, height: 8)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .offset(y: -(height - 20) * value - 6)
                VStack {
                    Text("\(Int((armed ? output : value) * 100))%")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("GAS")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 14)
            }
            .clipShape(Capsule())
            .glassCapsule(interactive: true)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if dragStart == nil { dragStart = value }
                        let start = dragStart ?? value
                        value = (start - gesture.translation.height / max(height * 0.85, 1)).clamped(to: 0...1)
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
        .sensoryFeedback(.selection, trigger: Int(value * 10)) { _, _ in haptics }
        .accessibilityElement()
        .accessibilityLabel("Gas")
        .accessibilityValue("\(Int(value * 100)) Prozent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.1)
            case .decrement: value = max(0, value - 0.1)
            @unknown default: break
            }
        }
    }
}

/// Horizontal self-centering rudder pad (joystick mode).
struct RudderPad: View {
    @Binding var value: Double
    var haptics: Bool
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let travel = (geo.size.width - geo.size.height) / 2
            ZStack {
                HStack {
                    Image(systemName: "arrow.left").opacity(0.5)
                    Spacer()
                    Text("RUDER").font(.caption2.weight(.heavy)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "arrow.right").opacity(0.5)
                }
                .padding(.horizontal, 22)
                Circle()
                    .fill(.white)
                    .overlay(Circle().fill(Theme.accent.opacity(isDragging ? 0.5 : 0.2)).padding(10))
                    .frame(width: geo.size.height - 14, height: geo.size.height - 14)
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    .offset(x: travel * value)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassCapsule(interactive: true)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        value = ((gesture.location.x - geo.size.width / 2) / max(travel, 1)).clamped(to: -1...1)
                    }
                    .onEnded { _ in
                        isDragging = false
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { value = 0 }
                    }
            )
        }
        .sensoryFeedback(.impact(weight: .light), trigger: abs(value) > 0.98) { _, new in haptics && new }
        .accessibilityLabel("Ruder")
    }
}

/// Visual feedback for tilt steering + calibration.
struct TiltIndicator: View {
    var input: Double
    var output: Double
    var onCalibrate: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let travel = geo.size.width / 2 - 12
                ZStack {
                    Capsule().fill(.white.opacity(0.08))
                    Rectangle().fill(.white.opacity(0.4)).frame(width: 1.5)
                    Capsule()
                        .fill(Theme.accent.opacity(0.35))
                        .frame(width: abs(output) * travel, height: 10)
                        .offset(x: output * travel / 2)
                    Circle()
                        .fill(.white)
                        .frame(width: 18, height: 18)
                        .offset(x: input * travel)
                        .shadow(radius: 3)
                }
            }
            .frame(height: 22)
            HStack {
                Label("Neigen", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Nullen", systemImage: "scope", action: onCalibrate)
                    .font(.caption.weight(.semibold))
                    .glassButtonStyle()
                    .controlSize(.small)
            }
        }
        .padding(14)
        .glassPanel(cornerRadius: 22)
        .animation(.interactiveSpring(response: 0.2), value: input)
    }
}

/// Hold to arm (prevents accidental motor start), tap to disarm.
struct ArmButton: View {
    var armed: Bool
    var enabled: Bool
    var haptics: Bool
    var onArm: () -> Void
    var onDisarm: () -> Void

    @State private var progress: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: armed ? "bolt.fill" : "lock.fill")
                .font(.headline)
                .symbolEffect(.pulse, isActive: armed)
            VStack(alignment: .leading, spacing: 1) {
                Text(armed ? "MOTOR SCHARF" : "Motor gesichert")
                    .font(.headline)
                Text(armed ? "Tippen zum Sichern" : (enabled ? "Gedrückt halten zum Scharfschalten" : "Erst Flugzeug verbinden"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(alignment: .leading) {
            GeometryReader { geo in
                Rectangle()
                    .fill(Theme.accent.opacity(0.45))
                    .frame(width: geo.size.width * progress)
            }
        }
        .clipShape(Capsule())
        .glassCapsule(tint: armed ? Theme.accent : nil, interactive: true)
        .opacity(enabled || armed ? 1 : 0.6)
        .contentShape(Capsule())
        .onTapGesture {
            if armed { onDisarm() }
        }
        .onLongPressGesture(minimumDuration: 0.7, maximumDistance: 40) {
            guard !armed, enabled else { return }
            progress = 0
            onArm()
        } onPressingChanged: { pressing in
            guard !armed, enabled else { return }
            withAnimation(pressing ? .linear(duration: 0.7) : .easeOut(duration: 0.2)) {
                progress = pressing ? 1 : 0
            }
        }
        .sensoryFeedback(.success, trigger: armed) { _, new in haptics && new }
        .sensoryFeedback(.warning, trigger: armed) { old, new in haptics && old && !new }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(armed ? "Motor sichern" : "Motor scharfschalten")
        .accessibilityAction { armed ? onDisarm() : onArm() }
    }
}

struct StopButton: View {
    var action: () -> Void
    @State private var trigger = 0

    var body: some View {
        Button {
            trigger += 1
            action()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "hand.raised.fill").font(.title2)
                Text("STOP").font(.caption2.weight(.black))
            }
            .foregroundStyle(.white)
            .frame(width: 62, height: 62)
        }
        .buttonStyle(.plain)
        .glassCircle(tint: Theme.danger, interactive: true)
        .sensoryFeedback(.impact(weight: .heavy), trigger: trigger)
        .accessibilityLabel("Not-Aus, Motor sofort abschalten")
    }
}

/// Top status capsule: connection, battery, signal, temperature.
struct StatusStrip: View {
    @Environment(AppModel.self) private var model
    var onTap: () -> Void

    var body: some View {
        let link = model.link
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .fill(link.isReady ? Theme.accent : (link.phase.isBusy ? Theme.warning : Color.gray))
                    .frame(width: 9, height: 9)
                    .shadow(color: link.isReady ? Theme.accent : .clear, radius: 5)
                VStack(alignment: .leading, spacing: 0) {
                    Text(link.isReady ? link.name : "SmartPlane")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(link.phase.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if link.isReady {
                    if let temperature = link.temperatureRaw {
                        Label("\(temperature)°", systemImage: "thermometer.medium")
                            .font(.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: batterySymbol(link.batteryPercent, charging: link.isCharging == true))
                            .foregroundStyle(Theme.batteryColor(link.batteryPercent))
                        if let percent = link.batteryPercent {
                            Text("\(percent)%").font(.caption.weight(.semibold)).monospacedDigit()
                        }
                    }
                    SignalBars(rssi: link.rssi)
                } else if link.phase.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassCapsule(interactive: true)
    }

    private func batterySymbol(_ percent: Int?, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        guard let percent else { return "battery.0percent" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
