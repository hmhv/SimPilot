import Foundation
import SimBridge
import XCTest

final class SimulatorKitPathTests: XCTestCase {
    private let fileManager = FileManager.default
    private var temporaryDirectory: URL!
    private var developerDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        developerDirectory = temporaryDirectory
            .appendingPathComponent("Xcode.app/Contents/Developer", isDirectory: true)
        try fileManager.createDirectory(
            at: developerDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try fileManager.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        developerDirectory = nil
    }

    func testUsesSharedFrameworksPath() {
        let sharedPath = temporaryDirectory
            .appendingPathComponent(
                "Xcode.app/Contents/SharedFrameworks/SimulatorKit.framework/SimulatorKit"
            )
        XCTAssertEqual(resolvePath(), sharedPath.path)
    }

    private func resolvePath() -> String {
        SPSimBridge.simulatorKitPath(forDeveloperDir: developerDirectory.path)
    }
}
