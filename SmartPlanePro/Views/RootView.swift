import SwiftUI

enum AppTab: Hashable {
    case cockpit, stunts, lab, settings
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: AppTab = .cockpit
    @State private var showOnboarding = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Cockpit", systemImage: "airplane", value: AppTab.cockpit) {
                CockpitView(openLab: { tab = .lab })
            }
            Tab("Stunts", systemImage: "sparkles", value: AppTab.stunts) {
                StuntsView(openCockpit: { tab = .cockpit }, openLab: { tab = .lab })
            }
            Tab("Labor", systemImage: "antenna.radiowaves.left.and.right", value: AppTab.lab) {
                LabView(openCockpit: { tab = .cockpit })
            }
            Tab("Einstellungen", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .modifier(TabBarMinimize())
        .onAppear {
            if !model.settings.hasSeenOnboarding { showOnboarding = true }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                model.settings.hasSeenOnboarding = true
                showOnboarding = false
            }
            .interactiveDismissDisabled()
        }
    }
}

private struct TabBarMinimize: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

struct OnboardingView: View {
    let onDone: () -> Void

    private struct Feature: Identifiable {
        let symbol: String
        let title: String
        let text: String
        var id: String { title }
    }

    private let features: [Feature] = [
        Feature(symbol: "airplane.departure", title: "Fliegen wie früher", text: "Neigungs- oder Joystick-Steuerung, Flight Assist, Trimmung und 8 Stunts – mit dem originalen SmartLink-Protokoll von TobyRich."),
        Feature(symbol: "antenna.radiowaves.left.and.right", title: "Bluetooth-Labor", text: "Falls dein Flugzeug anders spricht: scanne jedes BLE-Modul, lies Services, Firmware und Rohdaten und ordne Motor & Ruder selbst zu."),
        Feature(symbol: "hand.raised.fill", title: "Sicher zuerst", text: "Motor muss bewusst scharf geschaltet werden. Not-Aus ist immer sichtbar, beim Verlassen der App geht der Motor sofort aus."),
    ]

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(spacing: 28) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(Theme.accent.gradient)
                        .padding(28)
                        .glassCircle(tint: Theme.accent.opacity(0.3))
                        .padding(.top, 40)

                    VStack(spacing: 8) {
                        Text("SmartPlane PRO")
                            .font(.largeTitle.bold())
                            .fontDesign(.rounded)
                        Text("Die Steuer-App für dein TobyRich-Flugzeug – neu gebaut für iOS 26.")
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }

                    GlassGroup(spacing: 14) {
                        VStack(spacing: 14) {
                            ForEach(features) { feature in
                                HStack(alignment: .top, spacing: 16) {
                                    Image(systemName: feature.symbol)
                                        .font(.title2)
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 36)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(feature.title).font(.headline)
                                        Text(feature.text).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                .card()
                            }
                        }
                    }

                    Button(action: onDone) {
                        Text("Los geht's")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .glassButtonStyle(prominent: true)
                    .controlSize(.large)
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, 22)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
