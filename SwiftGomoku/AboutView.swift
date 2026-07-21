#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
import SwiftUI

struct AboutView: View {
    #if os(iOS)
    @State private var showingLicense = false
    #endif

    private let rapfiURL = URL(string: "https://github.com/dhbloo/rapfi")!
    private let rapfiSourceURL = URL(string: "https://github.com/dhbloo/rapfi/tree/3aedf3a2ab0ab710a9f3d00e57d5287ceb864894")!
    private let piskvorkURL = URL(string: "https://github.com/wind23/piskvork_renju")!

    var body: some View {
        VStack(spacing: 20) {
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)

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
        #if os(macOS)
        .frame(width: 500)
        #elseif os(iOS)
        .sheet(isPresented: $showingLicense) {
            LicenseView()
        }
        #endif
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
        #if os(macOS)
        guard let url = Bundle.main.url(forResource: "GPL-3.0", withExtension: "txt") else { return }
        NSWorkspace.shared.open(url)
        #elseif os(iOS)
        showingLicense = true
        #endif
    }
}

#if os(iOS)
struct LicenseView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var licenseText: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(licenseText)
                    .font(.caption.monospaced())
                    .padding()
            }
            .navigationTitle(L10n.text("about.view_license"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("button.done")) {
                        dismiss()
                    }
                }
            }
            .onAppear(perform: loadLicenseText)
        }
    }

    private func loadLicenseText() {
        guard let url = Bundle.main.url(forResource: "GPL-3.0", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            licenseText = "Unable to load license."
            return
        }
        licenseText = text
    }
}

struct AboutView_iOS: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                AboutView()
            }
            .navigationTitle(L10n.text("about.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("button.done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
#endif
