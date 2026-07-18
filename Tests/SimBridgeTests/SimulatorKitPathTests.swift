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

    func testUsesSharedFrameworksPathForXcode27() throws {
        let sharedPath = temporaryDirectory
            .appendingPathComponent(
                "Xcode.app/Contents/SharedFrameworks/SimulatorKit.framework/SimulatorKit"
            )
        try createBinary(at: sharedPath)

        XCTAssertEqual(resolvePath(), sharedPath.path)
    }

    func testUsesClassicPathForOlderXcode() throws {
        let classicPath = developerDirectory
            .appendingPathComponent(
                "Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"
            )
        try createBinary(at: classicPath)

        XCTAssertEqual(resolvePath(), classicPath.path)
    }

    func testPrefersSharedFrameworksWhenBothPathsExist() throws {
        let sharedPath = temporaryDirectory
            .appendingPathComponent(
                "Xcode.app/Contents/SharedFrameworks/SimulatorKit.framework/SimulatorKit"
            )
        let classicPath = developerDirectory
            .appendingPathComponent(
                "Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"
            )
        try createBinary(at: sharedPath)
        try createBinary(at: classicPath)

        XCTAssertEqual(resolvePath(), sharedPath.path)
    }

    func testFallsBackToClassicPathWhenNeitherExists() {
        let classicPath = developerDirectory
            .appendingPathComponent(
                "Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"
            )

        XCTAssertEqual(resolvePath(), classicPath.path)
    }

    private func resolvePath() -> String {
        SPSimBridge.simulatorKitPath(forDeveloperDir: developerDirectory.path)
    }

    private func createBinary(at url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(fileManager.createFile(atPath: url.path, contents: Data()))
    }
}
