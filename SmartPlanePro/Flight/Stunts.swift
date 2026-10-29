import Foundation

/// A pre-programmed manoeuvre: a list of keyframes that is played back by the
/// flight controller. Throttle values can be absolute or relative to the throttle
/// the pilot had when the stunt started.
struct Stunt: Identifiable, Hashable {
    struct Step: Hashable {
        enum Throttle: Hashable {
            case absolute(Double)
            /// Multiplier of the pilot's throttle at stunt start.
            case relative(Double)
            /// Keep whatever the pilot had.
            case hold
        }

        var duration: TimeInterval
        var throttle: Throttle
        var rudder: Double
        /// Interpolate from the previous step instead of jumping.
        var ramp: Bool = true
    }

    let id: String
    let name: String
    let symbol: String
    let summary: String
    let tip: String
    let difficulty: Int
    let steps: [Step]

    var duration: TimeInterval { steps.reduce(0) { $0 + $1.duration } }

    static let all: [Stunt] = [
        Stunt(
            id: "loop", name: "Looping", symbol: "arrow.trianglehead.clockwise", summary: "Vollgas-Impuls für einen sauberen Looping.",
            tip: "Aus ruhigem Geradeausflug mit ca. 60 % Gas starten. Höhenruder leicht nach oben trimmen.",
            difficulty: 3,
            steps: [
                Step(duration: 0.35, throttle: .absolute(1.0), rudder: 0),
                Step(duration: 2.4, throttle: .absolute(1.0), rudder: 0, ramp: false),
                Step(duration: 0.8, throttle: .relative(1.0), rudder: 0),
            ]
        ),
        Stunt(
            id: "steep-turn", name: "Steilkurve 360°", symbol: "arrow.clockwise.circle", summary: "Enge Vollkreis-Kurve nach rechts mit Kurvenschub.",
            tip: "Genug Höhe! In der Kurve verliert das Flugzeug Auftrieb – der Boost gleicht das aus.",
            difficulty: 2,
            steps: [
                Step(duration: 0.4, throttle: .absolute(0.85), rudder: 1.0),
                Step(duration: 3.0, throttle: .absolute(0.85), rudder: 1.0, ramp: false),
                Step(duration: 0.6, throttle: .relative(1.0), rudder: 0),
            ]
        ),
        Stunt(
            id: "spiral", name: "Spirale", symbol: "hurricane", summary: "Aufsteigende Spirale mit konstantem Ruder.",
            tip: "Startet am besten aus 70–80 % Gas, gleichmäßiger Wind ist ideal.",
            difficulty: 2,
            steps: [
                Step(duration: 0.5, throttle: .absolute(0.9), rudder: 0.65),
                Step(duration: 6.0, throttle: .absolute(0.9), rudder: 0.65, ramp: false),
                Step(duration: 0.8, throttle: .relative(1.0), rudder: 0),
            ]
        ),
        Stunt(
            id: "eight", name: "Liegende Acht", symbol: "infinity", summary: "Rechtskurve, kurz geradeaus, dann Linkskurve.",
            tip: "Perfekt zum Üben: mittlere Höhe, mittleres Gas.",
            difficulty: 2,
            steps: [
                Step(duration: 0.4, throttle: .absolute(0.8), rudder: 0.8),
                Step(duration: 2.6, throttle: .absolute(0.8), rudder: 0.8, ramp: false),
                Step(duration: 0.6, throttle: .absolute(0.8), rudder: 0),
                Step(duration: 0.4, throttle: .absolute(0.8), rudder: -0.8),
                Step(duration: 2.6, throttle: .absolute(0.8), rudder: -0.8, ramp: false),
                Step(duration: 0.6, throttle: .relative(1.0), rudder: 0),
            ]
        ),
        Stunt(
            id: "slalom", name: "Slalom", symbol: "point.topleft.down.to.point.bottomright.curvepath", summary: "Schnelle Links-Rechts-Wechsel.",
            tip: "Wirkt am besten im Tiefflug über einer Wiese.",
            difficulty: 1,
            steps: (0..<4).flatMap { index -> [Step] in
                let direction: Double = index.isMultiple(of: 2) ? 0.6 : -0.6
                return [
                    Step(duration: 0.3, throttle: .hold, rudder: direction),
                    Step(duration: 0.7, throttle: .hold, rudder: direction, ramp: false),
                ]
            } + [Step(duration: 0.4, throttle: .hold, rudder: 0)]
        ),
        Stunt(
            id: "boost", name: "Turbo-Boost", symbol: "bolt.fill", summary: "2 Sekunden volle Leistung, dann zurück.",
            tip: "Ideal zum schnellen Höhengewinn.",
            difficulty: 1,
            steps: [
                Step(duration: 0.2, throttle: .absolute(1.0), rudder: 0),
                Step(duration: 2.0, throttle: .absolute(1.0), rudder: 0, ramp: false),
                Step(duration: 0.6, throttle: .relative(1.0), rudder: 0),
            ]
        ),
        Stunt(
            id: "climb", name: "Steigflug", symbol: "arrow.up.forward", summary: "Kontrollierter Steigflug geradeaus.",
            tip: "Gegen den Wind ausführen.",
            difficulty: 1,
            steps: [
                Step(duration: 1.0, throttle: .absolute(0.95), rudder: 0),
                Step(duration: 3.5, throttle: .absolute(0.95), rudder: 0, ramp: false),
                Step(duration: 1.0, throttle: .relative(1.0), rudder: 0),
            ]
        ),
        Stunt(
            id: "landing", name: "Sanfte Landung", symbol: "airplane.arrival", summary: "Gas langsam auf null – das Flugzeug gleitet aus.",
            tip: "Gegen den Wind anfliegen, Flügel gerade halten.",
            difficulty: 1,
            steps: [
                Step(duration: 1.5, throttle: .relative(0.55), rudder: 0),
                Step(duration: 2.5, throttle: .absolute(0.0), rudder: 0),
            ]
        ),
    ]
}

/// Plays a stunt back in real time.
struct StuntPlayback {
    let stunt: Stunt
    let startDate: Date
    let baseThrottle: Double
    let baseRudder: Double

    func progress(at date: Date) -> Double {
        (date.timeIntervalSince(startDate) / stunt.duration).clamped(to: 0...1)
    }

    func isFinished(at date: Date) -> Bool {
        date.timeIntervalSince(startDate) >= stunt.duration
    }

    func output(at date: Date) -> (throttle: Double, rudder: Double) {
        var elapsed = date.timeIntervalSince(startDate)
        var previous: (throttle: Double, rudder: Double) = (baseThrottle, baseRudder)
        for step in stunt.steps {
            let target = (throttle: resolve(step.throttle), rudder: step.rudder)
            if elapsed < step.duration {
                guard step.ramp, step.duration > 0 else { return target }
                let t = elapsed / step.duration
                let eased = t * t * (3 - 2 * t)
                return (previous.throttle + (target.throttle - previous.throttle) * eased,
                        previous.rudder + (target.rudder - previous.rudder) * eased)
            }
            elapsed -= step.duration
            previous = target
        }
        return previous
    }

    private func resolve(_ throttle: Stunt.Step.Throttle) -> Double {
        switch throttle {
        case .absolute(let value): return value
        case .relative(let factor): return (baseThrottle * factor).clamped(to: 0...1)
        case .hold: return baseThrottle
        }
    }
}
