// Update.swift
//
// `sipi update` — check GitHub Releases for a newer sipi and self-replace.
//
// SimPilot ships as a single prebuilt binary via GitHub Releases. `update`:
//   1. GETs api.github.com/repos/hmhv/SimPilot/releases/latest and reads the tag.
//   2. Compares the tag to the running sipiVersion (semver).
//   3. If newer: downloads the release asset (the sipi binary) to a temp path,
//      strips the com.apple.quarantine xattr, then replaces ~/.local/bin/sipi
//      AND the running binary path, then re-execs the freshly installed binary as
//      `sipi setup` to lay down the NEW embedded skills (this process is still the
//      OLD binary, so an in-process setup would write the old skills).
//   4. If there is no release yet, or the running build is already latest, prints
//      a clear message and exits 0 (it is NOT an error to be up to date).
//
// If the re-exec cannot be launched we fall back to the in-process
// SkillInstaller.setup so update never leaves skills un-refreshed. If the re-exec
// runs but `sipi setup` exits non-zero, `update` exits non-zero too (the binary is
// already replaced, but we do not report success with stale/partial skills).

import ArgumentParser
import Foundation
import SimCore

extension Sipi {
    struct Update: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "update",
            abstract: "Update sipi to the latest GitHub release and refresh skills."
        )

        /// GitHub repo that publishes the sipi releases.
        static let releaseRepo = "hmhv/SimPilot"
        /// The prebuilt-binary asset name to prefer when a release has several.
        static let assetName = "sipi"

        func run() throws {
            guard let release = try Self.fetchLatestRelease() else {
                print("No SimPilot release published yet — nothing to update. (sipi \(sipiVersion))")
                return
            }

            guard let latest = SemanticVersion(release.tag) else {
                print("Latest release tag '\(release.tag)' is not a parseable version — staying on sipi \(sipiVersion).")
                return
            }

            guard let current = SemanticVersion(sipiVersion) else {
                throw ValidationError("Could not parse the running sipi version '\(sipiVersion)'.")
            }

            if latest <= current {
                print("sipi is already up to date (\(sipiVersion); latest release \(release.tag)).")
                return
            }

            print("Updating sipi \(sipiVersion) -> \(release.tag)...")

            guard let assetURL = release.binaryAssetURL(named: Self.assetName) else {
                throw ValidationError(
                    "The latest SimPilot release (\(release.tag)) has no `\(Self.assetName)` binary asset; cannot update. "
                        + "Download and install sipi manually from "
                        + "https://github.com/\(Self.releaseRepo)/releases/tag/\(release.tag)."
                )
            }

            let tempBinary = try Self.downloadBinary(from: assetURL)
            Self.stripQuarantine(at: tempBinary)
            let replaced = try Self.installBinary(from: tempBinary)

            print("Updated. Replaced:")
            for path in replaced {
                print("    \(path)")
            }

            // Refresh the embedded skills. This process is still the OLD binary, so
            // running SkillInstaller.setup in-process would materialize the OLD
            // skills. Instead re-exec the freshly installed binary so its NEW
            // embedded skills are laid down. If that fails to launch, fall back to
            // the in-process setup so update never leaves skills un-refreshed.
            switch Self.refreshSkillsByReexec() {
            case .ran(let status):
                // The binary was replaced; surface a failed `sipi setup` instead
                // of reporting success with stale/partial skills.
                if status != 0 { throw ExitCode.failure }
                return
            case .couldNotLaunch:
                break  // fall through to the in-process setup below
            }

            let setupResult = try SkillInstaller.setup(version: sipiVersion)
            print("  Skills refreshed (\(setupResult.fileCount) files) under:")
            for root in SkillInstaller.skillsRoots {
                print("    \(root.path)")
            }

            if setupResult.binNotOnPath {
                print("")
                FileHandle.standardError.write(Data((SkillInstaller.pathAdvice + "\n").utf8))
            }
        }

        /// Outcome of refreshing skills by re-execing the freshly installed binary.
        enum SkillRefresh {
            /// The child `sipi setup` launched; carries its exit status.
            case ran(Int32)
            /// The child could not be launched; the caller should fall back to the
            /// in-process setup.
            case couldNotLaunch
        }

        /// Re-exec the just-installed binary as `sipi setup` so the NEW embedded
        /// skills (not this old process's payload) are written.
        static func refreshSkillsByReexec() -> SkillRefresh {
            let process = Process()
            process.executableURL = SkillInstaller.installedBinary
            process.arguments = ["setup"]

            do {
                try process.run()
            } catch {
                FileHandle.standardError.write(
                    Data("Could not run the updated binary to refresh skills (\(error)); refreshing in-process.\n".utf8)
                )
                return .couldNotLaunch
            }

            process.waitUntilExit()
            if process.terminationStatus != 0 {
                FileHandle.standardError.write(
                    Data("The updated binary's `sipi setup` exited \(process.terminationStatus); skills may be stale.\n".utf8)
                )
            }
            return .ran(process.terminationStatus)
        }

        // MARK: - GitHub release metadata

        /// Minimal view of a GitHub release: its tag and downloadable assets.
        struct Release {
            let tag: String
            let assets: [(name: String, downloadURL: URL)]

            /// The asset whose name matches `named` exactly, else nil. We refuse to
            /// install an arbitrarily-named asset (which could brick the install with
            /// the wrong binary); this mirrors install.sh, which hard-fails when no
            /// asset named `sipi` exists.
            func binaryAssetURL(named: String) -> URL? {
                assets.first(where: { $0.name == named })?.downloadURL
            }
        }

        /// GET the latest release. Returns nil when GitHub reports no release
        /// (404) so the caller can treat "no release yet" as a clean exit 0.
        static func fetchLatestRelease() throws -> Release? {
            let url = URL(string: "https://api.github.com/repos/\(releaseRepo)/releases/latest")!
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("sipi-update", forHTTPHeaderField: "User-Agent")

            let (data, response) = try synchronousData(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                return nil
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw RuntimeError("GitHub release lookup failed (HTTP \(code)).")
            }

            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = object["tag_name"] as? String else {
                throw RuntimeError("Could not parse the GitHub release response.")
            }

            var assets: [(name: String, downloadURL: URL)] = []
            if let rawAssets = object["assets"] as? [[String: Any]] {
                for asset in rawAssets {
                    if let name = asset["name"] as? String,
                       let urlString = asset["browser_download_url"] as? String,
                       let assetURL = URL(string: urlString) {
                        assets.append((name: name, downloadURL: assetURL))
                    }
                }
            }
            return Release(tag: tag, assets: assets)
        }

        // MARK: - Download + install

        /// Download the release asset to a temp file, returning its URL.
        static func downloadBinary(from url: URL) throws -> URL {
            var request = URLRequest(url: url)
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            request.setValue("sipi-update", forHTTPHeaderField: "User-Agent")

            let (data, response) = try synchronousData(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw RuntimeError("Downloading the sipi binary failed (HTTP \(code)).")
            }

            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("sipi-update-\(UUID().uuidString)", isDirectory: false)
            try data.write(to: temp, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temp.path)
            return temp
        }

        /// Strip the com.apple.quarantine xattr so Gatekeeper does not block the
        /// freshly downloaded binary. Best-effort: a missing xattr is fine.
        static func stripQuarantine(at url: URL) {
            url.withUnsafeFileSystemRepresentation { pointer in
                guard let pointer else { return }
                _ = removexattr(pointer, "com.apple.quarantine", 0)
            }
        }

        /// Move the downloaded binary into place at ~/.local/bin/sipi and the
        /// running executable path (if different). Returns the paths replaced.
        static func installBinary(from source: URL) throws -> [String] {
            let fileManager = FileManager.default
            var replaced: [String] = []

            var targets: [URL] = [SkillInstaller.installedBinary]
            if let running = Sipi.Uninstall.runningExecutableURL(),
               running.path != SkillInstaller.installedBinary.resolvingSymlinksInPath().path {
                targets.append(running)
            }

            for target in targets {
                try fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = try Data(contentsOf: source)
                try data.write(to: target, options: .atomic)
                try fileManager.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: target.path
                )
                replaced.append(target.path)
            }

            try? fileManager.removeItem(at: source)
            return replaced
        }

        // MARK: - Synchronous networking

        /// Run a URLSession data task synchronously (ArgumentParser `run()` is sync).
        private static func synchronousData(for request: URLRequest) throws -> (Data, URLResponse) {
            let semaphore = DispatchSemaphore(value: 0)
            var result: Result<(Data, URLResponse), Error>?

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    result = .failure(error)
                } else if let data, let response {
                    result = .success((data, response))
                } else {
                    result = .failure(RuntimeError("Empty response from \(request.url?.absoluteString ?? "?")."))
                }
                semaphore.signal()
            }
            task.resume()
            semaphore.wait()

            switch result {
            case .success(let pair): return pair
            case .failure(let error): throw error
            case .none: throw RuntimeError("No response.")
            }
        }
    }
}

/// A simple, message-only error for the update flow.
struct RuntimeError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}
