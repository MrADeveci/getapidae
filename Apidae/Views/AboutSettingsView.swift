import SwiftUI

struct AboutSettingsView: View {
    private var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, build != short { return "\(short) (\(build))" }
        return short
    }

    private let repoURL = URL(string: "https://github.com/MrADeveci/getapidae")!
    private let lockpawURL = URL(string: "https://github.com/sorkila/lockpaw")!

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apidae")
                            .font(.title3.weight(.semibold))
                        Text("Version \(versionString)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Text("Apidae keeps your Mac awake while Claude works and covers the screen when you step away. It is a visual privacy tool: it prevents accidental input while the cover is active. For real security, use your Mac's lock screen (Ctrl+Cmd+Q).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Links") {
                LabeledContent("Source") {
                    Link("github.com/MrADeveci/getapidae", destination: repoURL)
                        .font(.callout)
                }
                LabeledContent("Upstream") {
                    Link("Forked from Lockpaw by Erik Nielsen", destination: lockpawURL)
                        .font(.callout)
                }
            }

            Section("Licence") {
                Text("Released under the MIT Licence. The original Lockpaw copyright and licence terms are preserved in the LICENSE file shipped with this app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 380, idealHeight: 460)
    }
}
