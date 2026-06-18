import AuthenticationServices
import PhotosUI
import SafariServices
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isFileImporterPresented = false
    @State private var isSafariPresented = false
    @State private var authSession: ASWebAuthenticationSession?
    @State private var status = "Ready"

    var body: some View {
        NavigationStack {
            List {
                Section("System UI") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Open PhotosPicker", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityIdentifier("system-ui.open-photos-picker")
                    .onChange(of: selectedPhoto) { _, item in
                        status = item == nil ? "No photo selected" : "Photo selected"
                    }

                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Label("Open FileImporter", systemImage: "doc")
                    }
                    .accessibilityIdentifier("system-ui.open-file-importer")

                    ShareLink(item: URL(string: "https://example.com/simpilot")!) {
                        Label("Open Share Sheet", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("system-ui.open-share-sheet")

                    Button {
                        isSafariPresented = true
                    } label: {
                        Label("Open SFSafariViewController", systemImage: "safari")
                    }
                    .accessibilityIdentifier("system-ui.open-safari")

                    Button {
                        startWebAuth()
                    } label: {
                        Label("Open ASWebAuthenticationSession", systemImage: "person.badge.key")
                    }
                    .accessibilityIdentifier("system-ui.open-web-auth")
                }

                Section("Status") {
                    Text(status)
                        .accessibilityIdentifier("system-ui.status")
                }
            }
            .navigationTitle("System UI Fixture")
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image, .plainText, .pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                status = "Imported \(urls.first?.lastPathComponent ?? "file")"
            case .failure(let error):
                status = "Import failed: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $isSafariPresented) {
            SafariView(url: URL(string: "https://example.com")!)
                .ignoresSafeArea()
        }
    }

    private func startWebAuth() {
        let url = URL(string: "https://example.com/simpilot-auth")!
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "simpilotfixture"
        ) { callbackURL, error in
            if let callbackURL {
                status = "Auth callback: \(callbackURL.absoluteString)"
            } else if let error {
                status = "Auth ended: \(error.localizedDescription)"
            } else {
                status = "Auth ended"
            }
            authSession = nil
        }
        session.presentationContextProvider = WebAuthPresentationContextProvider.shared
        session.prefersEphemeralWebBrowserSession = true
        authSession = session
        status = session.start() ? "Auth started" : "Auth failed to start"
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

final class WebAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthPresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
