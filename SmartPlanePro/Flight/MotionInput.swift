import CoreMotion
import Foundation
import Observation
import UIKit

/// Converts the phone's attitude into a steering angle, independent of how the
/// interface is rotated, and also provides roll/pitch for the artificial horizon.
@Observable
final class MotionInput {
    /// Sideways tilt in degrees (+ = right edge down), relative to the interface orientation.
    private(set) var tiltDegrees: Double = 0
    /// Forward/back tilt in degrees for the horizon animation.
    private(set) var pitchDegrees: Double = 0
    private(set) var isRunning = false
    private(set) var isAvailable = false

    private let manager = CMMotionManager()
    @ObservationIgnored private var users = Set<String>()
    @ObservationIgnored var interfaceOrientation: UIInterfaceOrientation = .portrait

    init() {
        isAvailable = manager.isDeviceMotionAvailable
    }

    func start(_ owner: String) {
        users.insert(owner)
        guard !isRunning, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.process(motion.gravity)
        }
        isRunning = true
    }

    func stop(_ owner: String) {
        users.remove(owner)
        guard users.isEmpty, isRunning else { return }
        manager.stopDeviceMotionUpdates()
        isRunning = false
    }

    private func process(_ gravity: CMAcceleration) {
        // Map device axes onto the axes of the current interface orientation.
        let lateral: Double
        let vertical: Double
        switch interfaceOrientation {
        case .landscapeLeft:
            lateral = gravity.y; vertical = -gravity.x
        case .landscapeRight:
            lateral = -gravity.y; vertical = gravity.x
        case .portraitUpsideDown:
            lateral = -gravity.x; vertical = -gravity.y
        default:
            lateral = gravity.x; vertical = gravity.y
        }
        // Works both for "steering wheel" (screen upright) and "tray" (screen flat) grips.
        let tilt = atan2(lateral, sqrt(vertical * vertical + gravity.z * gravity.z)) * 180 / .pi
        let pitch = atan2(-vertical, -gravity.z) * 180 / .pi
        // Light low-pass filter against hand jitter.
        tiltDegrees += (tilt - tiltDegrees) * 0.35
        pitchDegrees += (pitch - pitchDegrees) * 0.2
    }
}
