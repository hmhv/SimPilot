import Foundation
import XCTest
@testable import SimShell

final class NetworkConditionProviderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("network-condition-provider-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    func testProviderUsesArgvContractForApplyAndClear() throws {
        let executable = directory.appendingPathComponent("provider")
        let log = directory.appendingPathComponent("arguments.log")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> "\(log.path)"
        if [ "$1" = "status" ]; then
          printf '{"profiles":["offline"]}\\n'
        fi
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let provider = try NetworkConditionProvider(path: executable.path)
        XCTAssertTrue(try provider.status().contains("offline"))
        try provider.apply(profile: "packet-loss-100", udid: "device-1", bundleID: "com.example.app")
        try provider.clear(udid: "device-1", bundleID: "com.example.app")

        let lines = try String(contentsOf: log, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        XCTAssertEqual(lines, [
            "status --json",
            "apply --udid device-1 --bundle-id com.example.app --profile packet-loss-100",
            "clear --udid device-1 --bundle-id com.example.app"
        ])
    }

    func testProviderRejectsRelativePathAndUnsafeProfile() throws {
        XCTAssertThrowsError(try NetworkConditionProvider(path: "provider"))

        let executable = directory.appendingPathComponent("provider")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let provider = try NetworkConditionProvider(path: executable.path)
        XCTAssertThrowsError(
            try provider.apply(profile: "../../offline", udid: "device", bundleID: "com.example.app")
        )
    }
}
