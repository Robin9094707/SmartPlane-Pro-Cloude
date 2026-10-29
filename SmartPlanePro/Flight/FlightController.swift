import Foundation
import Observation
import UIKit

/// Combines pilot inputs (tilt, on-screen joystick, gamepad, stunts), applies
/// expo / trim / flight assist and drives `PlaneLink` at a fixed rate.
@Observable
final class FlightController {
    // Pilot inputs
    var throttleInput: Double = 0
    var joystickRudder: Double = 0
    private(set) var isArmed = false
    private(set) var stunt: StuntPlayback?
    private(set) var stuntProgress: Double = 0
    /// Direct test output used by the system check (bypasses arming for small values).
    private(set) var testOverride: (throttle: Double, rudder: Double)?

    // Outputs actually sent (after mixing)
    private(set) var throttleOutput: Double = 0
    private(set) var rudderOutput: Double = 0
    private(set) var rudderInputRaw: Double = 0
    private(set) var flightTime: TimeInterval = 0

    let link: PlaneLink
    let settings: AppSettings
    let motion: MotionInput
    let gamepad: GamepadInput
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTick = Date()
    @ObservationIgnored private var smoothedThrottle: Double = 0
    @ObservationIgnored private var lastGamepadThrottle: Double = 0

    init(link: PlaneLink, settings: AppSettings, motion: MotionInput, gamepad: GamepadInput) {
        self.link = link
        self.settings = settings
        self.motion = motion
        self.gamepad = gamepad
        gamepad.onCut = { [weak self] in self?.cutMotor() }
        gamepad.onArmToggle = { [weak self] in
            guard let self else { return }
            if self.isArmed { self.disarm() } else { _ = self.arm() }
        }
        restartLoop()
    }

    func restartLoop() {
        timer?.invalidate()
        let interval = 1.0 / settings.sendRateHz.clamped(to: 5...60)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Arming / safety

    enum ArmError: Error { case notConnected, throttleNotZero }

    @discardableResult
    func arm() -> Result<Void, ArmError> {
        guard link.isReady else { return .failure(.notConnected) }
        if settings.requireZeroThrottleToArm && throttleInput > 0.02 && !gamepadActive {
            return .failure(.throttleNotZero)
        }
        isArmed = true
        flightTime = 0
        appLog(.info, "Flug", "Motor scharf geschaltet")
        return .success(())
    }

    func disarm() {
        guard isArmed || stunt != nil else { return }
        isArmed = false
        stunt = nil
        throttleInput = 0
        smoothedThrottle = 0
        link.sendNeutral()
        appLog(.info, "Flug", "Motor gesichert")
    }

    /// Emergency stop: motor off immediately, rudder centred.
    func cutMotor() {
        isArmed = false
        stunt = nil
        testOverride = nil
        throttleInput = 0
        smoothedThrottle = 0
        link.sendNeutral()
        appLog(.warning, "Flug", "NOT-AUS: Motor abgeschaltet")
    }

    func calibrateTilt() {
        settings.tiltOffset = motion.tiltDegrees
    }

    // MARK: - Stunts & tests

    func run(_ stunt: Stunt) {
        guard isArmed else { return }
        self.stunt = StuntPlayback(stunt: stunt, startDate: Date(), baseThrottle: max(throttleInput, 0.5), baseRudder: rudderOutput)
        appLog(.info, "Stunt", "\(stunt.name) gestartet")
    }

    func cancelStunt() {
        if let stunt { appLog(.info, "Stunt", "\(stunt.stunt.name) abgebrochen") }
        stunt = nil
    }

    /// Used by the system check to move the rudder / spin the motor briefly.
    func setTestOutput(throttle: Double, rudder: Double) {
        testOverride = (throttle.clamped(to: 0...0.35), rudder.clamped(to: -1...1))
    }

    func clearTestOutput() {
        testOverride = nil
        link.sendNeutral()
    }

    private var gamepadActive: Bool { settings.gamepadEnabled && gamepad.isConnected }

    // MARK: - Control loop

    private func tick() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), 0.2)
        lastTick = now

        guard link.isReady else {
            if isArmed { isArmed = false; stunt = nil }
            throttleOutput = 0
            rudderOutput = 0
            return
        }

        if let test = testOverride {
            throttleOutput = test.throttle
            rudderOutput = test.rudder
            link.send(throttle: test.throttle, rudder: test.rudder)
            return
        }

        // 1. Raw pilot input
        var rudder: Double
        var throttle = throttleInput.clamped(to: 0...1)
        if gamepadActive {
            rudder = gamepad.rudder
            if gamepad.throttle > 0.01 || lastGamepadThrottle > 0.01 {
                throttleInput = gamepad.throttle
                throttle = gamepad.throttle
            }
            lastGamepadThrottle = gamepad.throttle
        } else if settings.controlMode == .tilt {
            let angle = motion.tiltDegrees - settings.tiltOffset
            rudder = (angle / max(settings.tiltMaxAngle, 5)).clamped(to: -1...1)
        } else {
            rudder = joystickRudder.clamped(to: -1...1)
        }
        rudderInputRaw = rudder

        // 2. Shaping: deadzone → expo → rate → trim → reverse
        rudder = Self.shape(rudder, deadzone: settings.deadzone, expo: settings.expo) * settings.rudderRate
        rudder = (rudder + settings.rudderTrim).clamped(to: -1...1)
        if settings.rudderReversed { rudder = -rudder }

        // 3. Stunt playback overrides the pilot
        if let playback = stunt {
            if playback.isFinished(at: now) {
                appLog(.info, "Stunt", "\(playback.stunt.name) beendet")
                stunt = nil
                stuntProgress = 0
            } else {
                let output = playback.output(at: now)
                throttle = output.throttle
                rudder = output.rudder
                stuntProgress = playback.progress(at: now)
            }
        }

        // 4. Flight assist (same ideas as TobyRich's app): soften the left-pulling
        //    rudder and add throttle in turns to compensate lost lift.
        if settings.flightAssist {
            if rudder < 0 { rudder *= settings.leftRudderScale }
            if settings.turnBoost && throttle > 0.05 {
                let boost = min(0.3, 1 - cos(abs(rudder) * .pi / 2))
                throttle = min(1, throttle * (1 + boost))
            }
        }
        throttle = min(throttle, settings.maxThrottle)

        // 5. Throttle slew-rate limit for smooth motor response
        if settings.throttleRampSeconds > 0.01 {
            let maxStep = dt / settings.throttleRampSeconds
            smoothedThrottle += (throttle - smoothedThrottle).clamped(to: -maxStep...maxStep)
        } else {
            smoothedThrottle = throttle
        }

        if !isArmed {
            smoothedThrottle = 0
        } else if smoothedThrottle > 0.05 {
            flightTime += dt
        }

        throttleOutput = smoothedThrottle
        rudderOutput = rudder
        link.send(throttle: throttleOutput, rudder: rudderOutput)
    }

    static func shape(_ value: Double, deadzone: Double, expo: Double) -> Double {
        let magnitude = abs(value)
        guard magnitude > deadzone else { return 0 }
        let scaled = (magnitude - deadzone) / (1 - deadzone)
        let curved = (1 - expo) * scaled + expo * scaled * scaled * scaled
        return value < 0 ? -curved : curved
    }
}
