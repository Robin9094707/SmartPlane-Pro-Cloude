import Foundation
import GameController
import Observation

/// Optional hardware controller support (Xbox, PlayStation, MFi …).
/// Right trigger / left stick Y = throttle, left stick X = rudder,
/// B / Circle = motor cut, Menu = arm toggle.
@Observable
final class GamepadInput {
    private(set) var controllerName: String?
    private(set) var throttle: Double = 0
    private(set) var rudder: Double = 0
    private(set) var throttleFromStick = false

    @ObservationIgnored var onCut: (() -> Void)?
    @ObservationIgnored var onArmToggle: (() -> Void)?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    var isConnected: Bool { controllerName != nil }

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            if let controller = note.object as? GCController { self?.configure(controller) }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if let next = GCController.controllers().first {
                self.configure(next)
            } else {
                self.controllerName = nil
                self.throttle = 0
                self.rudder = 0
            }
        })
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        if let existing = GCController.controllers().first { configure(existing) }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    private func configure(_ controller: GCController) {
        controllerName = controller.vendorName ?? "Controller"
        appLog(.info, "Gamepad", "\(controllerName ?? "Controller") verbunden")
        guard let pad = controller.extendedGamepad else { return }
        pad.valueChangedHandler = { [weak self] gamepad, _ in
            guard let self else { return }
            let trigger = Double(gamepad.rightTrigger.value)
            let stickY = Double(gamepad.leftThumbstick.yAxis.value)
            if trigger > 0.02 {
                self.throttle = trigger
                self.throttleFromStick = false
            } else if stickY > 0.05 {
                self.throttle = stickY
                self.throttleFromStick = true
            } else {
                self.throttle = 0
            }
            let stickX = Double(gamepad.leftThumbstick.xAxis.value)
            let rightX = Double(gamepad.rightThumbstick.xAxis.value)
            self.rudder = abs(stickX) >= abs(rightX) ? stickX : rightX
        }
        pad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onCut?() }
        }
        pad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onArmToggle?() }
        }
    }
}
