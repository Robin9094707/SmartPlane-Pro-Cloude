import Foundation
import Observation

/// Root object graph, injected into the SwiftUI environment.
@Observable
final class AppModel {
    let settings: AppSettings
    let central: BLECentral
    let link: PlaneLink
    let motion: MotionInput
    let gamepad: GamepadInput
    let flight: FlightController
    let log = EventLog.shared

    init() {
        let settings = AppSettings()
        let central = BLECentral()
        let link = PlaneLink(central: central, settings: settings)
        let motion = MotionInput()
        let gamepad = GamepadInput()
        self.settings = settings
        self.central = central
        self.link = link
        self.motion = motion
        self.gamepad = gamepad
        self.flight = FlightController(link: link, settings: settings, motion: motion, gamepad: gamepad)
        appLog(.info, "App", "SmartPlane PRO Control gestartet")
    }

    /// Called when the app leaves the foreground: never leave a motor running.
    func enterBackground() {
        flight.cutMotor()
    }
}
