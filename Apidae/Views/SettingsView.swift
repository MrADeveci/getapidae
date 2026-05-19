import SwiftUI

struct SettingsView: View {
    let statsService: StatsService?

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }

            StatsSettingsView(statsService: statsService)
                .tabItem { Label("Stats", systemImage: "chart.bar") }

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 400, idealWidth: 480, maxWidth: 560)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
