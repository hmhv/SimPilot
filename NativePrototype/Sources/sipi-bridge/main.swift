import Foundation
import SimBridge

// Headless CLI over the SimBridge native bridge. Mirrors how `axe` is invoked
// from Bash, but reaches System UI that AXe cannot see. JSON on stdout for
// `ax` and `devices`.

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func emitJSON(_ object: Any) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]) else {
        die("failed to encode JSON")
    }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

let usage = """
usage:
  sipi-bridge devices
  sipi-bridge status
  sipi-bridge ax <udid>                         # accessibility tree as JSON (sees System UI)
  sipi-bridge tap <udid> <nx> <ny>              # normalized 0...1
  sipi-bridge swipe <udid> <x1> <y1> <x2> <y2>  # normalized 0...1
  sipi-bridge button <udid> <name>             # home|lock|side_button|app_switcher|siri|swipe_home
  sipi-bridge key <udid> <hid-usage>           # e.g. 40 = Return, 42 = Backspace
  sipi-bridge orientation <udid> <name>        # portrait|landscape-left|landscape-right|portrait-upside-down
  sipi-bridge multitouch <udid> <phase> <x1> <y1> <x2> <y2>
  sipi-bridge crown <udid> <delta>             # Apple Watch simulators only
  sipi-bridge screenshot <udid> <path>
"""

let args = CommandLine.arguments
guard args.count >= 2 else { die(usage) }
let dev = SPSimBridge.defaultDeveloperDir()
let command = args[1]

func arg(_ i: Int, _ what: String) -> String {
    guard args.count > i else { die("missing \(what)\n\n\(usage)") }
    return args[i]
}
func num(_ i: Int, _ what: String) -> Double {
    guard args.count > i, let v = Double(args[i]) else { die("invalid \(what)\n\n\(usage)") }
    return v
}
func norm(_ i: Int, _ what: String) -> Double {
    let v = num(i, what)
    guard v >= 0.0 && v <= 1.0 else { die("\(what) must be normalized 0...1\n\n\(usage)") }
    return v
}
func deviceName(for udid: String) throws -> String {
    let devices = try SPSimBridge.listDevices(forDeveloperDir: dev)
    return devices.first { $0.udid.caseInsensitiveCompare(udid) == .orderedSame }?.name ?? ""
}
func setOrientation(_ requested: String, udid: String) throws {
    let menuName: String
    switch requested.lowercased().replacingOccurrences(of: "_", with: "-") {
    case "portrait":
        menuName = "Portrait"
    case "landscape-left", "left":
        menuName = "Landscape Left"
    case "landscape-right", "right", "landscape":
        menuName = "Landscape Right"
    case "portrait-upside-down", "upside-down":
        menuName = "Portrait Upside Down"
    case "face-up":
        menuName = "Face Up"
    case "face-down":
        menuName = "Face Down"
    default:
        die("invalid orientation '\(requested)'\n\n\(usage)")
    }
    let name = try deviceName(for: udid)
    let script = """
    on run argv
      set deviceName to item 1 of argv
      set targetOrientation to item 2 of argv
      tell application "Simulator" to activate
      delay 0.2
      tell application "System Events"
        tell process "Simulator"
          if deviceName is not "" then
            repeat with w in windows
              if name of w contains deviceName then
                perform action "AXRaise" of w
                exit repeat
              end if
            end repeat
          end if
          click menu item targetOrientation of menu 1 of menu item "Orientation" of menu 1 of menu bar item "Device" of menu bar 1
        end tell
      end tell
    end run
    """
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-", name, menuName]
    let input = Pipe()
    let output = Pipe()
    let error = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = error
    try process.run()
    input.fileHandleForWriting.write(Data(script.utf8))
    input.fileHandleForWriting.closeFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let message = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "osascript failed"
        die("orientation: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
}

do {
    switch command {
    case "devices":
        let devices = try SPSimBridge.listDevices(forDeveloperDir: dev)
        emitJSON(devices.map { [
            "udid": $0.udid, "name": $0.name, "state": $0.stateString,
            "booted": $0.isBooted, "runtime": $0.runtimeName ?? ""
        ] })

    case "status":
        print(SPSimBridge.accessibilityBridgeStatus())

    case "ax":
        let tree = try SPSimBridge.accessibilityTree(forUDID: arg(2, "udid"), developerDir: dev)
        emitJSON(tree)

    case "tap":
        try SPSimBridge.tapUDID(arg(2, "udid"), normalizedX: norm(3, "nx"), y: norm(4, "ny"), developerDir: dev)
        print("ok")

    case "swipe":
        let udid = arg(2, "udid")
        let x1 = norm(3, "x1"), y1 = norm(4, "y1"), x2 = norm(5, "x2"), y2 = norm(6, "y2")
        try SPSimBridge.touchUDID(udid, phase: 1, normalizedX: x1, y: y1, developerDir: dev)
        let steps = 10
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            try SPSimBridge.touchUDID(udid, phase: 1, normalizedX: x1 + (x2 - x1) * t, y: y1 + (y2 - y1) * t, developerDir: dev)
            usleep(15 * 1000)
        }
        try SPSimBridge.touchUDID(udid, phase: 2, normalizedX: x2, y: y2, developerDir: dev)
        print("ok")

    case "button":
        try SPSimBridge.pressButton(arg(3, "name"), udid: arg(2, "udid"), developerDir: dev)
        print("ok")

    case "key":
        let udid = arg(2, "udid")
        guard let usage = UInt(arg(3, "hid-usage")) else { die("invalid hid-usage") }
        try SPSimBridge.sendKeyUsage(usage, down: true, udid: udid, developerDir: dev)
        try SPSimBridge.sendKeyUsage(usage, down: false, udid: udid, developerDir: dev)
        print("ok")

    case "orientation":
        try setOrientation(arg(3, "name"), udid: arg(2, "udid"))
        print("ok")

    case "multitouch":
        let udid = arg(2, "udid")
        guard let phase = Int(arg(3, "phase")) else { die("invalid phase\n\n\(usage)") }
        try SPSimBridge.multiTouchUDID(udid, phase: phase, x1: norm(4, "x1"), y1: norm(5, "y1"), x2: norm(6, "x2"), y2: norm(7, "y2"), developerDir: dev)
        print("ok")

    case "crown":
        try SPSimBridge.sendDigitalCrownDelta(num(3, "delta"), udid: arg(2, "udid"), developerDir: dev)
        print("ok")

    case "screenshot":
        let udid = arg(2, "udid"), path = arg(3, "path")
        try SPSimBridge.writeFramebufferPNG(forUDID: udid, developerDir: dev, toPath: path)
        print(path)

    default:
        die("unknown command '\(command)'\n\n\(usage)")
    }
} catch {
    die("\(command): \(error.localizedDescription)")
}
