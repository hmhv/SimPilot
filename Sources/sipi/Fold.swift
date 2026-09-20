// Fold.swift
//
// `sipi fold <udid>` — fold or unfold a foldable simulator (iPhone Duo).
//
// The write half of `fold-state`. Nothing in Xcode 27.1 exposes this: simctl has
// no verb, devicectl's `motion hinge-angle` only reads, and Device Hub's own
// slider is hidden behind an internal action bar. HingeControl explains how the
// angle actually gets there, and who the mechanism is derived from.
//
// The two poses that matter to a test are the ends of the range, so they have
// names: `--closed` is 0 and `--open` is 180. `--angle` covers everything
// between, including the partly-folded poses an app can lay out for.

import ArgumentParser
import Foundation
import SimCore
import SimNative
import SimShell

extension Sipi {
    struct Fold: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "fold",
            abstract: "Fold or unfold a foldable simulator by setting its hinge angle."
        )

        @Argument(help: "Simulator UDID.")
        var udid: String

        @Option(name: .long, help: "Hinge angle in degrees, 0 (shut) to 180 (flat open).")
        var angle: Double?

        @Flag(name: .long, help: "Shut the device (0°). The cover screen takes over.")
        var closed = false

        @Flag(name: .long, help: "Open the device flat (180°). The inner screen takes over.")
        var open = false

        @Option(
            name: .long,
            help: """
            Sweep to the angle over this many seconds instead of jumping in one \
            event, the way dragging Device Hub's slider does. Use it when the app \
            animates on the fold — a jump can skip what it was meant to react to.
            """
        )
        var over: Double?

        @Flag(name: .long, help: "Emit the resulting fold state as JSON, as `fold-state` would.")
        var json = false

        func validate() throws {
            let named = [angle != nil, closed, open].filter { $0 }.count
            guard named == 1 else {
                throw ValidationError("fold takes exactly one of --angle, --closed, or --open.")
            }
            if let angle, !HingeControl.range.contains(angle) {
                throw ValidationError(
                    "--angle must be between \(Int(HingeControl.range.lowerBound)) and "
                    + "\(Int(HingeControl.range.upperBound)) degrees; got \(angle)."
                )
            }
            if let over, over < 0 {
                throw ValidationError("--over must not be negative.")
            }
        }

        func run() throws {
            let displays = (try? DeviceCtl.displays(udid: udid)) ?? []
            // Refuse early and specifically. Sending the event to a phone is not
            // an error anywhere in the stack — it is silently ignored — so
            // without this check `fold` would report success on a device that
            // has no hinge.
            guard displays.count > 1 else {
                throw ValidationError(
                    displays.isEmpty
                        ? "Cannot read this device's screens, so sipi cannot tell whether it folds. "
                          + "`devicectl device info displays` only answers for booted simulators on Xcode 27+."
                        : "This device does not fold: it has one built-in screen. "
                          + "Only iPhone Duo has a hinge."
                )
            }

            let target = angle ?? (closed ? HingeControl.range.lowerBound : HingeControl.range.upperBound)
            try HingeControl.setAngle(udid: udid, degrees: target, over: over)

            // Report what the device ended up at rather than what was asked for.
            // The angle is applied asynchronously and the screen handover follows
            // it, so a caller that needs the new pose needs the reading, not the
            // request.
            let settled = settledState(target: target)
            if json {
                let data = try JSONSerialization.data(
                    withJSONObject: settled.object,
                    options: [.prettyPrinted, .sortedKeys]
                )
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            } else {
                print(settled.line)
            }
        }

        /// Poll until the lit screen agrees with the new angle, then report what
        /// the device says rather than what was asked for.
        ///
        /// Waiting for "some screen is lit" is not enough: the old screen is
        /// still lit for a moment after the angle changes, so the first reading
        /// after a fold describes the pose that just ended. Waiting for the
        /// screen the angle IMPLIES is what makes the next command see the new
        /// one. Between the two measured handover points the angle implies
        /// neither, so there is nothing to wait for and the first lit screen is
        /// the answer.
        private func settledState(target: Double) -> (line: String, object: [String: Any]) {
            let expected = HingeControl.impliedRole(atAngle: target)

            var displays: [DeviceDisplay] = []
            var lit: DeviceDisplay?
            var roles: [Int: DisplayRole] = [:]
            let deadline = Date().addingTimeInterval(3)
            repeat {
                displays = (try? DeviceCtl.displays(udid: udid)) ?? []
                roles = DisplaySelection.roles(displays)
                lit = DisplaySelection.active(displays)
                if let lit, expected == nil || roles[lit.screenID] == expected { break }
                Thread.sleep(forTimeInterval: 0.1)
            } while Date() < deadline

            let folded = DisplaySelection.isFolded(displays)
            let reading = DeviceCtl.hingeAngle(udid: udid)

            var object: [String: Any] = [
                "folded": folded as Any? ?? NSNull(),
                "hingeAngle": reading as Any? ?? NSNull(),
                "activeDisplay": lit.map { $0.screenID } as Any? ?? NSNull()
            ]
            if let lit {
                let role = (roles[lit.screenID] ?? .screen).rawValue
                object["activeRole"] = role
                object["pointSize"] = [lit.pointWidth, lit.pointHeight]
                let angleText = reading.map { String(format: "%g", $0) } ?? "?"
                return ("\(angleText)° \(role) \(lit.pointWidth)x\(lit.pointHeight)pt", object)
            }
            return ("no screen lit", object)
        }
    }
}
