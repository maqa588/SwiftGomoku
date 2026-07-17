import AppKit
import SwiftUI

struct AboutView: View {
    private let rapfiURL = URL(string: "https://github.com/dhbloo/rapfi")!
    private let rapfiSourceURL = URL(string: "https://github.com/dhbloo/rapfi/tree/3aedf3a2ab0ab710a9f3d00e57d5287ceb864894")!
    private let piskvorkURL = URL(string: "https://github.com/wind23/piskvork_renju")!

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            VStack(spacing: 4) {
                Text("Swift Gomoku")
                    .font(.title.bold())
                Text(L10n.format("about.version", version))
                    .foregroundStyle(.secondary)
            }

            Text(L10n.text("about.gpl_summary"))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox(L10n.text("about.open_source")) {
                VStack(spacing: 0) {
                    projectLink(
                        title: "dhbloo/rapfi",
                        detail: L10n.text("about.rapfi_detail"),
                        destination: rapfiURL
                    )
                    Divider()
                    projectLink(
                        title: L10n.text("about.rapfi_source"),
                        detail: "3aedf3a · ARM64 NEON",
                        destination: rapfiSourceURL
                    )
                    Divider()
                    projectLink(
                        title: "wind23/piskvork_renju",
                        detail: L10n.text("about.piskvork_detail"),
                        destination: piskvorkURL
                    )
                }
            }

            HStack {
                Button(L10n.text("about.view_license"), action: openLocalLicense)
                Spacer()
                Text("GPL-3.0-only")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(width: 500)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func projectLink(title: String, detail: String, destination: URL) -> some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).fontWeight(.medium)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func openLocalLicense() {
        guard let url = Bundle.main.url(forResource: "GPL-3.0", withExtension: "txt") else { return }
        NSWorkspace.shared.open(url)
    }
}
