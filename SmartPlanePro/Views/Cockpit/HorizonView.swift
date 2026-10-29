import SwiftUI

/// Full-screen artificial horizon. Rolls opposite to the phone's tilt so the
/// horizon stays level with the real one, just like a cockpit instrument.
struct HorizonView: View {
    var roll: Double
    var pitch: Double

    var body: some View {
        Canvas { context, size in
            let diagonal = hypot(size.width, size.height) * 1.6
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let pitchOffset = CGFloat((pitch - 40).clamped(to: -50...50)) * size.height / 140

            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: .degrees(-roll))
            context.translateBy(x: 0, y: pitchOffset)

            let skyRect = CGRect(x: -diagonal / 2, y: -diagonal, width: diagonal, height: diagonal)
            context.fill(Path(skyRect), with: .linearGradient(
                Gradient(colors: Theme.sky),
                startPoint: CGPoint(x: 0, y: -size.height * 0.9),
                endPoint: CGPoint(x: 0, y: 0)
            ))
            let groundRect = CGRect(x: -diagonal / 2, y: 0, width: diagonal, height: diagonal)
            context.fill(Path(groundRect), with: .linearGradient(
                Gradient(colors: Theme.ground),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height * 0.9)
            ))

            // Soft glow on the horizon line
            context.fill(
                Path(CGRect(x: -diagonal / 2, y: -30, width: diagonal, height: 60)),
                with: .linearGradient(
                    Gradient(colors: [.clear, .white.opacity(0.22), .clear]),
                    startPoint: CGPoint(x: 0, y: -30), endPoint: CGPoint(x: 0, y: 30)
                )
            )
            var line = Path()
            line.move(to: CGPoint(x: -diagonal / 2, y: 0))
            line.addLine(to: CGPoint(x: diagonal / 2, y: 0))
            context.stroke(line, with: .color(.white.opacity(0.8)), lineWidth: 1.5)

            // Pitch ladder
            for step in stride(from: -30, through: 30, by: 10) where step != 0 {
                let y = CGFloat(-step) * size.height / 140
                let width: CGFloat = step % 20 == 0 ? 90 : 50
                var rung = Path()
                rung.move(to: CGPoint(x: -width / 2, y: y))
                rung.addLine(to: CGPoint(x: width / 2, y: y))
                context.stroke(rung, with: .color(.white.opacity(0.35)), lineWidth: 1)
            }

            // Perspective grid on the ground for a feeling of speed
            for index in 1...8 {
                let y = pow(CGFloat(index) / 8, 2) * size.height * 0.9
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: -diagonal / 2, y: y))
                gridLine.addLine(to: CGPoint(x: diagonal / 2, y: y))
                context.stroke(gridLine, with: .color(.white.opacity(0.06)), lineWidth: 1)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Roll scale and fixed aircraft symbol drawn on top of the horizon.
struct AttitudeOverlay: View {
    var roll: Double
    var rudder: Double

    var body: some View {
        ZStack {
            // Roll scale arc
            Circle()
                .trim(from: 0.62, to: 0.88)
                .stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 10]))
                .frame(width: 220, height: 220)
            // Roll pointer
            Triangle()
                .fill(Theme.accent)
                .frame(width: 14, height: 12)
                .offset(y: -122)
                .rotationEffect(.degrees(roll.clamped(to: -60...60)))
            // Aircraft symbol, yawing with the rudder
            Image(systemName: "airplane")
                .font(.system(size: 54, weight: .semibold))
                .rotationEffect(.degrees(-90 + rudder * 25))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
        }
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8), value: rudder)
        .accessibilityHidden(true)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
