import SwiftUI

struct StatsSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Stats")
                .font(.title3.weight(.semibold))
            Text("Lock and unlock activity will appear here.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
