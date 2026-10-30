// XcodeInstall.swift
//
// `sipi xcode install <build>` — download an Xcode release from Apple and put
// it in /Applications. Xcode has no official command-line installer: the
// release list comes from xcodereleases.com, and the archive needs an Apple
// Developer web session, which the user signs into in a window sipi opens.
// Nothing from that session is stored.

import AppKit
import ArgumentParser
import Foundation
import WebKit

extension Sipi {
    struct XcodeCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "xcode",
            abstract: "Install Xcode releases.",
            subcommands: [List.self, Install.self, Uninstall.self]
        )

        struct List: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "list",
                abstract: "List the Xcode releases of this macOS's generation and the one before whose minimum macOS this Mac meets, newest first. Betas only with --beta."
            )

            @Flag(help: "Include betas.")
            var beta = false

            func run() throws {
                let releases = try XcodeRelease.parse(HTTP.get(XcodeRelease.catalog))
                var seen = Set<String>()
                // The catalog gives only a minimum macOS; older Xcodes would all
                // pass it. Keep this macOS's generation and the one before.
                let generation = ProcessInfo.processInfo.operatingSystemVersion.majorVersion - 1
                for release in releases where (beta || ["release", "rc"].contains(release.channel))
                    && release.requires.map(XcodeRelease.hostRuns) ?? true
                    && (Int(release.version.split(separator: ".").first ?? "") ?? 0) >= generation
                    && seen.insert(release.build).inserted {
                    let name = release.displayName.padding(toLength: 16, withPad: " ", startingAt: 0)
                    let build = release.build.padding(toLength: 10, withPad: " ", startingAt: 0)
                    print("\(name)\(build)\(release.date)  macOS \(release.requires ?? "?")+")
                }
            }
        }

        struct Install: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "install",
                abstract: "Download an Xcode release from Apple and install it into /Applications.",
                discussion: """
                Look the build number up with `sipi xcode list` (add --beta for betas). When several
                entries share it, the release beats the RC, the RC beats a beta, and the
                Apple silicon archive beats the Universal one.

                A window opens on developer.apple.com: sign in there and it closes by
                itself. The session lives only in memory for this run.

                The app lands at /Applications/Xcode-<version>.app. Selecting it needs
                root, so sipi only prints the commands for that.
                """
            )

            @Argument(help: "Build number, e.g. 27B48.")
            var build: String

            func run() throws {
                let release = try XcodeRelease.resolve(build: build)
                if let requires = release.requires, !XcodeRelease.hostRuns(requires) {
                    throw ValidationError("Xcode \(release.displayName) needs macOS \(requires) or later")
                }
                guard release.appName.range(of: "^Xcode-[A-Za-z0-9._-]+\\.app$", options: .regularExpression) != nil,
                      !release.appName.contains("..") else {
                    throw ValidationError("unexpected version in the catalog: \(release.version)")
                }
                if let existing = installedXcodes().first(where: { installedBuild(of: $0) == release.build }) {
                    throw ValidationError("build \(release.build) is already installed at \(existing.path)")
                }
                let destination = URL(fileURLWithPath: "/Applications/\(release.appName)")
                guard !FileManager.default.fileExists(atPath: destination.path) else {
                    throw ValidationError("\(destination.path) already exists")
                }
                FileHandle.standardError.write(Data("Xcode \(release.displayName) (\(release.build)): \(release.url.absoluteString)\n".utf8))

                // A fixed name, so a run killed by a signal (which skips the defer)
                // is cleaned up by the next one.
                let stage = URL(fileURLWithPath: "/Applications/.sipi-xcode-install")
                try? FileManager.default.removeItem(at: stage)
                try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: stage) }
                let cookies = try AppleSignInWindow.signIn()

                let archive = stage.appendingPathComponent(release.url.lastPathComponent)
                try AppleDownload.download(release.url, to: archive, cookies: cookies)
                try XcodeArchive.expand(archive, in: stage)
                try FileManager.default.removeItem(at: archive)
                let app = try XcodeArchive.verifiedApp(in: stage, build: release.build)
                try FileManager.default.moveItem(at: app, to: destination)

                print("Installed \(destination.path)")
                print("To use it, run:")
                print("  sudo xcode-select -s \(destination.path)")
                print("  sudo xcodebuild -runFirstLaunch")
            }
        }
    }
}

extension Sipi.XcodeCommand {
    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "uninstall",
            abstract: "Move an installed Xcode in /Applications to the Trash. Refuses the selected one."
        )

        @Argument(help: "Build number of the installed Xcode (e.g. 27A9275), or its path when two share a build.")
        var build: String

        func run() throws {
            let apps = build.contains("/")
                ? installedXcodes().filter { $0.path == URL(fileURLWithPath: build).standardizedFileURL.path }
                : installedXcodes().filter { installedBuild(of: $0) == build }
            guard apps.count == 1, let app = apps.first else {
                throw ValidationError(apps.isEmpty
                    ? "no Xcode \(build) in /Applications"
                    : "several Xcodes have build \(build); pass one path: \(apps.map(\.path).joined(separator: ", "))")
            }
            let appPath = app.resolvingSymlinksInPath().path
            let inUse = [ProcessInfo.processInfo.environment["DEVELOPER_DIR"], systemDeveloperDir()].compactMap { $0 }
            if inUse.contains(where: { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path.hasPrefix(appPath + "/")
                || URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == appPath }) {
                throw ValidationError("\(app.path) is the selected Xcode; select another one first")
            }
            if NSWorkspace.shared.runningApplications.contains(where: {
                guard let path = $0.bundleURL?.resolvingSymlinksInPath().path else { return false }
                return path == appPath || path.hasPrefix(appPath + "/")
            }) {
                throw ValidationError("\(app.path) is running; quit it first")
            }
            do {
                try FileManager.default.trashItem(at: app, resultingItemURL: nil)
            } catch {
                throw ValidationError("could not move \(app.path) to the Trash (\(error.localizedDescription)); an App Store install is owned by root — ask the user to drag it to the Trash in Finder")
            }
            print("Moved \(app.path) to the Trash")
        }

    }
}

/// The system-wide selection. `xcode-select -p` reports DEVELOPER_DIR when it
/// is set, so it runs without it.
func systemDeveloperDir() -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    process.arguments = ["-p"]
    var environment = ProcessInfo.processInfo.environment
    environment["DEVELOPER_DIR"] = nil
    process.environment = environment
    let out = Pipe()
    process.standardOutput = out
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return process.terminationStatus == 0 && !path.isEmpty ? path : nil
}

func installedXcodes() -> [URL] {
    ((try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications"), includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.pathExtension == "app" && $0.lastPathComponent.hasPrefix("Xcode")
            && (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true }
}

func installedBuild(of app: URL) -> String? {
    let plist = app.appendingPathComponent("Contents/version.plist")
    return (try? Data(contentsOf: plist))
        .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }?["ProductBuildVersion"] as? String
}

struct XcodeRelease {
    let version: String
    let build: String
    let channel: String
    let channelNumber: Int?
    let url: URL
    let date: String
    let requires: String?

    static let catalog = URL(string: "https://xcodereleases.com/data.json")!

    var displayName: String {
        guard channel != "release" else { return version }
        return "\(version) \(channel)" + (channelNumber.map { " \($0)" } ?? "")
    }

    /// Matches the names xcodes gives, e.g. `Xcode-27.2.0-release.candidate.app`.
    var appName: String {
        var parts = version.split(separator: ".").map(String.init)
        while parts.count < 3 { parts.append("0") }
        var name = "Xcode-" + parts.joined(separator: ".")
        switch channel {
        case "release":
            break
        case "rc":
            name += "-release.candidate" + (channelNumber.flatMap { $0 > 1 ? ".\($0)" : nil } ?? "")
        default:
            name += "-\(channel)" + (channelNumber.map { ".\($0)" } ?? "")
        }
        return name + ".app"
    }

    private var rank: Int {
        let channelRank = channel == "release" ? 0 : channel == "rc" ? 1 : 2
        return channelRank * 2 + (url.lastPathComponent.contains("Universal") ? 1 : 0)
    }

    static func hostRuns(_ requires: String) -> Bool {
        let parts = requires.split(separator: ".").compactMap { Int($0) }
        let needed = OperatingSystemVersion(
            majorVersion: parts.first ?? 0,
            minorVersion: parts.count > 1 ? parts[1] : 0,
            patchVersion: parts.count > 2 ? parts[2] : 0)
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(needed)
    }

    static func resolve(build: String) throws -> XcodeRelease {
        let data = try HTTP.get(catalog)
        let matches = try parse(data).filter { $0.build == build }
        guard let best = matches.min(by: { $0.rank < $1.rank }) else {
            throw ValidationError("no Xcode with build \(build) at \(catalog.absoluteString)")
        }
        return best
    }

    static func parse(_ data: Data) throws -> [XcodeRelease] {
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ValidationError("unexpected format at \(catalog.absoluteString)")
        }
        return entries.compactMap { entry in
            guard let version = entry["version"] as? [String: Any],
                  let number = version["number"] as? String,
                  let build = version["build"] as? String,
                  let release = version["release"] as? [String: Any],
                  let channel = release.keys.first,
                  let links = entry["links"] as? [String: Any],
                  let download = links["download"] as? [String: Any],
                  let link = download["url"] as? String,
                  let url = URL(string: link),
                  url.scheme == "https", url.host == "download.developer.apple.com",
                  url.pathExtension == "xip",
                  // The catalog is third-party and its strings reach the agent.
                  number.range(of: "^[0-9.]+$", options: .regularExpression) != nil,
                  build.range(of: "^[0-9A-Za-z]+$", options: .regularExpression) != nil,
                  channel.range(of: "^[a-zA-Z]+$", options: .regularExpression) != nil,
                  (entry["requires"] as? String)?.range(of: "^[0-9.]+$", options: .regularExpression) != nil
                      || entry["requires"] == nil
            else { return nil }
            let day = entry["date"] as? [String: Int]
            let date = day.map { String(format: "%04d-%02d-%02d", $0["year"] ?? 0, $0["month"] ?? 0, $0["day"] ?? 0) } ?? ""
            return XcodeRelease(
                version: number, build: build, channel: channel,
                channelNumber: release[channel] as? Int, url: url,
                date: date, requires: entry["requires"] as? String)
        }
    }
}

enum HTTP {
    static func get(_ url: URL) throws -> Data {
        var result: Result<Data, Error> = .failure(ValidationError("no response from \(url.absoluteString)"))
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: url) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode
            if let error {
                result = .failure(error)
            } else if let data, status == 200 {
                result = .success(data)
            } else if let status {
                result = .failure(ValidationError("HTTP \(status) from \(url.absoluteString)"))
            }
            done.signal()
        }.resume()
        done.wait()
        return try result.get()
    }
}

enum AppleDownload {
    static let listDownloads = URL(string: "https://developer.apple.com/services-account/QH65B2/downloadws/listDownloads.action")!

    static func session(cookies: [HTTPCookie], delegate: URLSessionDelegate? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 6 * 60 * 60
        for cookie in cookies { configuration.httpCookieStorage?.setCookie(cookie) }
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    /// Whether the session can list downloads. The same call also issues the
    /// cookie download.developer.apple.com asks for, so it runs again right
    /// before every download.
    static func isSignedIn(_ session: URLSession, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: listDownloads)
        request.httpMethod = "POST"
        session.dataTask(with: request) { data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return completion(false) }
            completion(object["resultCode"] as? Int == 0)
        }.resume()
    }

    static func download(_ url: URL, to destination: URL, cookies: [HTTPCookie]) throws {
        let progress = DownloadProgress(destination: destination)
        let session = session(cookies: cookies, delegate: progress)
        defer { session.invalidateAndCancel() }

        let signedIn = DispatchSemaphore(value: 0)
        var ok = false
        isSignedIn(session) { ok = $0; signedIn.signal() }
        signedIn.wait()
        guard ok else { throw ValidationError("the Apple Developer session was refused; run again and sign in") }

        session.downloadTask(with: url).resume()
        progress.done.wait()
        if let error = progress.error { throw error }
    }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate {
    let destination: URL
    let done = DispatchSemaphore(value: 0)
    var error: Error?
    private var lastPercent = -5

    init(destination: URL) { self.destination = destination }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let percent = Int(totalBytesWritten * 100 / totalBytesExpectedToWrite)
        guard percent / 5 != lastPercent / 5 else { return }
        lastPercent = percent
        let gb = { (bytes: Int64) in String(format: "%.1f", Double(bytes) / 1_000_000_000) }
        FileHandle.standardError.write(Data("downloaded \(gb(totalBytesWritten)) of \(gb(totalBytesExpectedToWrite)) GB (\(percent)%)\n".utf8))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let response = downloadTask.response as? HTTPURLResponse
        // An expired session is answered with a sign-in page, not an error status.
        if response?.statusCode != 200 || response?.mimeType?.contains("html") == true {
            error = ValidationError("Apple did not send the archive (HTTP \(response?.statusCode ?? 0)); run again and sign in")
            return
        }
        do {
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            self.error = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, self.error == nil { self.error = error }
        done.signal()
    }
}

enum XcodeArchive {
    static let appleTeamID = "59GAB85EFG"

    static func expand(_ archive: URL, in directory: URL) throws {
        FileHandle.standardError.write(Data("expanding \(archive.lastPathComponent) (this takes several minutes)\n".utf8))
        try run("/usr/bin/xip", ["--expand", archive.path], in: directory)
    }

    static func verifiedApp(in directory: URL, build: String) throws -> URL {
        let apps = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "app" }
        guard apps.count == 1, let app = apps.first else {
            throw ValidationError("the archive did not contain exactly one app")
        }
        guard installedBuild(of: app) == build else {
            throw ValidationError("the archive holds a different build than \(build)")
        }
        let signature = try run("/usr/bin/codesign", ["-dv", "--verbose=4", app.path], in: directory)
        guard signature.split(separator: "\n").contains("TeamIdentifier=\(appleTeamID)") else {
            throw ValidationError("\(app.lastPathComponent) is not signed by Apple")
        }
        FileHandle.standardError.write(Data("checking the signature with Gatekeeper\n".utf8))
        try run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path], in: directory)
        return app
    }

    /// Returns stderr: codesign writes its details there.
    @discardableResult
    private static func run(_ tool: String, _ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        let output = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ValidationError("\(tool) \(arguments.joined(separator: " ")) failed: \(output)")
        }
        return output
    }
}

final class AppleSignInWindow: NSObject, NSWindowDelegate, NSApplicationDelegate {
    static let start = URL(string: "https://developer.apple.com/download/all/")!

    private let webView: WKWebView
    private let window: NSWindow
    private var timer: Timer?
    private var checking = false
    private let deadline = Date().addingTimeInterval(15 * 60)
    private var cookies: [HTTPCookie]?

    static func signIn() throws -> [HTTPCookie] {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.mainMenu = editMenu()
        let signIn = AppleSignInWindow()
        app.delegate = signIn
        signIn.window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        signIn.timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in signIn.check() }
        app.run()
        app.setActivationPolicy(.prohibited)
        // The caller blocks the main thread for the whole download; without one
        // more pass the closed window and the Dock icon stay on screen, frozen.
        let deadline = Date().addingTimeInterval(0.3)
        while let event = app.nextEvent(matching: .any, until: deadline, inMode: .default, dequeue: true) {
            app.sendEvent(event)
        }
        guard let cookies = signIn.cookies else { throw ValidationError("not signed in: the window was closed, or 15 minutes passed without a sign-in") }
        return cookies
    }

    /// Without a menu carrying these key equivalents, ⌘V never reaches the web
    /// view, and a password cannot be pasted into Apple's sign-in form.
    private static func editMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        let menu = NSMenu()
        menu.addItem(NSMenuItem())
        menu.addItem(editItem)
        return menu
    }

    private override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 720), configuration: configuration)
        window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        super.init()
        window.title = "Sign in to Apple Developer — sipi"
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        webView.load(URLRequest(url: Self.start))
    }

    private func check() {
        if Date() > deadline {
            window.close()
            return
        }
        guard !checking else { return }
        checking = true
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { all in
            let apple = all.filter { $0.domain.hasSuffix("apple.com") }
            let session = AppleDownload.session(cookies: apple)
            AppleDownload.isSignedIn(session) { signedIn in
                session.invalidateAndCancel()
                DispatchQueue.main.async {
                    self.checking = false
                    guard signedIn, self.cookies == nil else { return }
                    self.cookies = apple
                    self.window.close()
                }
            }
        }
    }

    /// Quit from the Dock would otherwise exit(0) inside `run()`, reporting
    /// success and skipping the staging cleanup.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        window.close()
        return .terminateCancel
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        let app = NSApplication.shared
        app.stop(nil)
        // stop(_:) takes effect only after the run loop handles another event.
        app.postEvent(
            NSEvent.otherEvent(
                with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!,
            atStart: false)
    }
}
