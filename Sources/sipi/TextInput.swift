// TextInput.swift
//
// Text-entry policy for `sipi type`. The default inserts text by copying it
// onto the simulator pasteboard and pressing Cmd+V, which is independent of the guest keyboard layout and active input
// language/IME — exactly the things that make US-layout HID keystrokes flaky.
// Keyboard injection stays available as an explicit opt-in for the rare field
// that must receive real per-character keystrokes.

import Foundation
import SimBridge
import SimCore
import SimShell

/// How `type` text reaches the focused field.
enum TextInputMethod: String {
    /// Copy onto the simulator pasteboard and press Cmd+V. Layout/IME independent.
    case paste
    /// Inject US-keyboard HID keystrokes. Requires US-representable text.
    case keyboard
    /// Hand the text to Xcode's own device-interaction service, which types it
    /// through a path that is neither HID nor layout-dependent. Needs Xcode 27
    /// with `sudo xcrun mcp-server enable`; see XcodeMCP.swift.
    case xcodeMCP = "xcode-mcp"
}

struct TextInputError: Error, CustomStringConvertible {
    let description: String
}

enum TextInput {
    /// Insert `text` into the focused field (first responder). `paste` (the
    /// default) clobbers and restores the simulator pasteboard on a best-effort
    /// basis; `keyboard` requires US-keyboard-representable text and errors
    /// otherwise so a test never silently types the wrong characters.
    ///
    /// Both methods insert at the caret, so a field that already holds text ends
    /// up with the two concatenated. Pass `clear: true` to select all (Cmd+A) and
    /// delete first. `clear` only clears reliably when no IME composition is
    /// pending (see `KeyInput.clearFieldEvents`); for a field that must simply end
    /// up holding a given value, the accessibility write behind `sipi set-text` is
    /// the deterministic path — it needs no keyboard at all.
    static func insert(
        _ text: String,
        method: TextInputMethod,
        clear: Bool = false,
        driver: SimDriver,
        udid: String,
        verifyEffect: Bool = true,
        developerDir: String? = nil
    ) throws {
        // WHERE the baseline is read decides which question the check asks, and
        // the right question depends on what this call is for.
        //
        // Emptying a field (`--clear` with no text) is asking the clear to be the
        // whole effect, so the baseline must precede it — reading after would
        // compare an emptied field against itself and fail every successful clear.
        //
        // Every other call is asking the INSERTION to have an effect, so the
        // baseline follows the clear. Reading before would fail the two idioms
        // that legitimately end where they started: `--clear` with the same
        // string, and clearing a SecureField to retype a password of the same
        // length (bullets either way).
        //
        // On a simulator that has stopped delivering keyboard HID (paste,
        // --keyboard and --clear all become no-ops) every call below still
        // "succeeds", which is why the field contents are the only honest signal.
        //
        // `probe` carries both the baseline and the depth it was read at, so the
        // after-read compares like with like. A nil probe means the check is off.
        //
        // The baseline THROWS when there is nowhere to type or the tree cannot be
        // read, and it is always taken before any text is sent, so those two
        // conditions fail the call without touching the device. Reporting them
        // after the insertion would mean a retried step types the text twice.
        // Rejected before anything reaches the device — before even the baseline
        // read: the clear below is itself keystrokes, and a rejection that came
        // after it would have already mutated the field, while one that came
        // after a failed read would report the wrong error.
        if method == .xcodeMCP && clear {
            // Select-all and delete are keystrokes, and Xcode's service types but
            // does not clear. Running the clear through HID and the insertion
            // through the service would leave a dead-HID device holding the old
            // value with the new text appended, while every check passed because
            // the field did change.
            throw TextInputError(description:
                "--clear cannot be combined with --xcode-mcp: the service types text but cannot "
                + "empty a field, and the select-all/delete keystrokes are exactly what a device "
                + "in this state is dropping. Use `sipi set-text` to replace the value outright.")
        }
        if method == .keyboard, !TextToHIDEvents.validateText(text) {
            throw TextInputError(description:
                "--keyboard cannot type text containing non-US-keyboard "
                + "characters (accented letters, non-Latin scripts, emoji); use the default paste method.")
        }

        // Put back after the effect check, not straight after Cmd+V: the guest
        // handles the paste asynchronously, and a restore that lands first would
        // paste the user's own clipboard into the app.
        var savedPasteboard: String?
        defer { if let savedPasteboard { try? SimShell.pbcopy(savedPasteboard, udid: udid) } }

        let clearIsTheEffect = clear && text.isEmpty
        var probe = verifyEffect && clearIsTheEffect ? try baseline(driver: driver, udid: udid) : nil

        // What the field held before the clear, kept only when the baseline will be
        // read after it. The clear is asynchronous — the keystrokes return long
        // before the guest applies them — so a baseline read straight afterward can
        // still see the OLD value. That poisons the comparison: `--clear` plus the
        // same string would then look unchanged and fail. `settledBaseline` waits
        // for the field to actually move off this value first.
        let preClear: String? = {
            guard verifyEffect, clear, !clearIsTheEffect else { return nil }
            if case .fields(let fingerprint) = read(driver: driver, udid: udid, deep: false) { return fingerprint }
            if case .fields(let fingerprint) = read(driver: driver, udid: udid, deep: true) { return fingerprint }
            return nil
        }()

        // Refuse before the clear keystrokes when there is no field to type into.
        if verifyEffect, clear, !clearIsTheEffect, preClear == nil {
            _ = try baseline(driver: driver, udid: udid)
        }

        if clear {
            for event in KeyInput.clearFieldEvents() {
                try driver.key(usage: event.usage, down: event.down, udid: udid)
                // Same pacing as keyboard injection: Cmd+A and the delete that
                // consumes the selection are dropped when sent back-to-back.
                usleep(12 * 1000)
            }
        }

        if verifyEffect && !clearIsTheEffect {
            probe = try settledBaseline(driver: driver, udid: udid, changedFrom: preClear)
        }

        switch method {
        case .keyboard:
            for event in try TextToHIDEvents.convertTextToHIDEvents(text) {
                try driver.key(usage: event.usage, down: event.down, udid: udid)
                // Pace events: sent back-to-back the guest keyboard coalesces and
                // drops trailing characters. A short gap lets each keystroke register.
                usleep(12 * 1000)
            }
        case .paste:
            // The paste target is the first responder, so the field must already
            // be focused. Save and restore the user's prior pasteboard best-effort.
            // The simulator pasteboard is kept in sync with the HOST pasteboard in
            // both directions, so this transiently replaces the Mac clipboard too
            // — the deferred restore is what puts the user's clipboard back.
            savedPasteboard = try? SimShell.pbpaste(udid: udid)
            try SimShell.pbcopy(text, udid: udid)
            // Read it back before pasting. While Device Hub is open it can put the
            // Mac's clipboard over what was just written, and Cmd+V would then
            // type the user's own clipboard into the app — measured on Xcode
            // 27.2, where that text went on to a web search.
            guard (try? SimShell.pbpaste(udid: udid)) == text else {
                throw TextInputError(description:
                    "the simulator's pasteboard did not keep the text, so nothing was pasted — "
                    + "something replaced it right after it was written (Device Hub does this with "
                    + "the Mac's clipboard while it is open). Quitting Device Hub shuts the simulator "
                    + "down, so boot it again (`xcrun simctl boot <udid>`) before retrying, or use "
                    + "`sipi set-text`, which needs no pasteboard.")
            }
            for event in KeyInput.pasteCombo() {
                try driver.key(usage: event.usage, down: event.down, udid: udid)
            }

        case .xcodeMCP:
            try typeViaXcode(text, udid: udid, developerDir: developerDir)
        }

        guard let probe else { return }
        // No automatic retry through Xcode's service when the keystrokes did not
        // land. It was tried: measured on Xcode 27.0 RC / iOS 27.0 24A434, one
        // device-interaction session leaves every app launched afterwards on that
        // device with an empty accessibility tree until the device restarts — the
        // same breakage as turning VoiceOver off after on. A fallback that fired
        // mid-run would wreck the rest of the run for a reason nothing reports.
        // `--xcode-mcp` remains available where a caller asks for it and can plan
        // the restart.
        try assertEffect(
            probe: probe,
            method: method,
            clearIsTheEffect: clearIsTheEffect,
            driver: driver,
            udid: udid
        )
    }

    /// Send `text` through Xcode's device-interaction service, translating its
    /// failures into `TextInputError`.
    private static func typeViaXcode(_ text: String, udid: String, developerDir: String?) throws {
        do {
            try XcodeMCP.typeText(text, udid: udid, developerDir: resolvedDeveloperDir(developerDir))
        } catch let reason as XcodeMCP.Unavailable {
            throw TextInputError(description: reason.description)
        }
    }

    private static func resolvedDeveloperDir(_ explicit: String?) -> String {
        explicit ?? SPSimBridge.defaultDeveloperDir()
    }

    /// The pre-insertion reading: the text-entry content plus the tree depth it
    /// was found at.
    private struct Probe {
        let fingerprint: String
        let deep: Bool
    }

    /// One reading of the text-entry state.
    ///
    /// Three outcomes, not two. Collapsing "the tree says there is no field" into
    /// "the tree could not be read" is what made the check report a stalled
    /// accessibility bridge as a missing field — and, downstream, made a field
    /// that legitimately disappeared look like a failed read.
    private enum Reading {
        /// The tree was read and at least one text-entry element was present.
        case fields(String)
        /// The tree was read and held no text-entry element.
        case noFields
        /// The tree could not be read at all.
        case unreadable
    }

    /// Read the text-entry content at one depth.
    ///
    /// Deliberately NOT the whole tree: the status bar clock is in there, so a
    /// whole-tree comparison reports a change every second whether or not the text
    /// arrived — the check would always pass and catch nothing.
    private static func read(driver: SimDriver, udid: String, deep: Bool) -> Reading {
        guard let nodes = try? driver.describe(udid, deep: deep), !ChildTree.isDegenerate(nodes) else { return .unreadable }
        guard let fingerprint = TextEntryProbe.fingerprint(roots: nodes) else { return .noFields }
        return .fields(fingerprint)
    }

    /// Read the baseline, escalating to the deep grid pass when the fast tree
    /// shows no text-entry element or cannot be read.
    ///
    /// The escalation is not optional: a FOCUSED field can leave the frontmost
    /// child tree entirely. Measured on iOS 26.4 — tapping Settings' search field
    /// removes the TextField from the fast tree while the deep pass still reports
    /// it. Without this, typing into a focused search field would fail as "no text
    /// field on screen".
    ///
    /// The cost lands only on the screens that need it: a field visible in the
    /// fast tree never triggers a grid pass.
    ///
    /// Throws rather than returning a nil baseline, and every caller takes it
    /// BEFORE sending any text: "nowhere to type" and "cannot read the tree" are
    /// both reasons not to type at all. Reporting them afterward would leave a
    /// retried step inserting the text a second time.
    private static func baseline(driver: SimDriver, udid: String) throws -> Probe {
        if case .fields(let fingerprint) = read(driver: driver, udid: udid, deep: false) {
            return Probe(fingerprint: fingerprint, deep: false)
        }
        switch read(driver: driver, udid: udid, deep: true) {
        case .fields(let fingerprint):
            return Probe(fingerprint: fingerprint, deep: true)
        case .noFields:
            throw TextInputError(description:
                "text entry not attempted: " + TextEntryProbe.Reason.noTextEntryElement.message)
        case .unreadable:
            throw TextInputError(description:
                """
                text entry not attempted: the accessibility tree could not be read, so there is no way \
                to tell whether the text lands. Nothing was typed, so this is safe to retry — right after \
                a launch the tree can take a second or two to appear. Do NOT toggle VoiceOver to "re-prime" \
                it: on iOS 27, off-after-on is what leaves the tree empty until the device restarts. \
                Pass --no-verify to type without the check.
                """)
        }
    }

    /// Read the baseline once the clear has actually landed.
    ///
    /// `changedFrom` is what the field held BEFORE the clear. The clear is
    /// asynchronous, so reading immediately after sending its keystrokes can
    /// return that same stale value; using it as the baseline makes a subsequent
    /// insertion of the identical string look like nothing happened. Poll until
    /// the field reads as something else, then take that as the baseline.
    ///
    /// Bounded and forgiving on purpose: a clear that never lands (a pending IME
    /// composition swallows the select-all, or the runtime drops keyboard HID) is
    /// NOT reported here. That is the insertion check's job, and failing here
    /// would misattribute it to the clear.
    private static func settledBaseline(
        driver: SimDriver,
        udid: String,
        changedFrom: String?
    ) throws -> Probe {
        guard let changedFrom else { return try baseline(driver: driver, udid: udid) }
        let deadline = Date().addingTimeInterval(clearSettleTimeout)
        var latest = try baseline(driver: driver, udid: udid)
        while latest.fingerprint == changedFrom, Date() < deadline {
            usleep(useconds_t(effectPollInterval * 1_000_000))
            latest = try baseline(driver: driver, udid: udid)
        }
        return latest
    }

    /// Fail when text entry provably did nothing.
    ///
    /// A real insertion changes the target field's value — a secure field shows
    /// bullets, which still differs from empty. An unchanged value therefore means
    /// the keystrokes never landed, which is exactly what a simulator whose
    /// keyboard HID has decayed does. Reporting `ok` there is worse than failing:
    /// the caller is told the input arrived while the app never saw it.
    ///
    /// This is intentionally a one-way check. A changed field is not proof the
    /// RIGHT text arrived (check that with `wait-for --text` or use `set-text`),
    /// but an unchanged field IS proof nothing arrived.
    private static func assertEffect(
        probe: Probe,
        method: TextInputMethod,
        clearIsTheEffect: Bool,
        driver: SimDriver,
        udid: String
    ) throws {
        // The guest applies the insertion asynchronously; poll briefly rather than
        // sleeping a fixed amount so a fast device stays fast.
        //
        // A failed read is retried, never treated as a pass. Returning on the
        // first failure would hand the worst case a green step: a runtime that
        // drops the keystrokes AND has a wobbly accessibility bridge — a worn-out
        // simulator has both — would report success having entered nothing.
        //
        // The verdict comes from the LAST reading, not from whether any reading
        // ever succeeded. Right after the keystrokes the field often still holds
        // its old value; treating that stale read as proof would let a bridge that
        // dies immediately afterward be reported as "nothing arrived" when the
        // truth is that the final state was never observed.
        var lastReading = Reading.unreadable
        let deadline = Date().addingTimeInterval(effectTimeout)
        repeat {
            lastReading = read(driver: driver, udid: udid, deep: probe.deep)
            switch lastReading {
            case .fields(let after):
                if TextEntryProbe.failureReason(before: probe.fingerprint, after: after) == nil { return }
            case .noFields:
                // The field is gone — the keyboard dismissed, a sheet closed, the
                // screen moved on. Something plainly happened, so this is a change,
                // not a no-op.
                return
            case .unreadable:
                break
            }
            usleep(useconds_t(effectPollInterval * 1_000_000))
        } while Date() < deadline

        if case .unreadable = lastReading {
            throw TextInputError(
                description: """
                    could not verify text entry (\(method.rawValue)): the accessibility tree could not be \
                    read back, so whether the text arrived is unknown — the text WAS sent, so re-running \
                    may enter it twice. Wait and read the field with `sipi describe-ui` before deciding; do \
                    NOT toggle VoiceOver to "re-prime" the tree, which is what empties it on iOS 27. \
                    Pass --no-verify to skip the check.
                    """
            )
        }

        // Name the operation that actually failed. For an empty-text clear the
        // insertion is not the subject — the clear is — and telling the user their
        // keystrokes never arrived would point at the wrong thing.
        if clearIsTheEffect {
            throw TextInputError(description:
                """
                clear had no effect: the text field's content is unchanged, so Cmd+A and delete \
                never arrived. On a simulator that has stopped delivering keyboard HID, use \
                `sipi set-text <udid> "" --id <id> --no-verify`, which empties the field through the \
                accessibility bridge. A pending IME composition also swallows the select-all — send \
                `sipi key 41 <udid>` (Escape) first. Pass --no-verify to skip this check.
                """)
        }
        throw TextInputError(description:
            "text entry had no effect (\(method.rawValue)): " + TextEntryProbe.Reason.unchanged.message)
    }

    /// How long to wait for a clear to show up in the field before taking the
    /// baseline anyway. Shorter than `effectTimeout` because the common case where
    /// it expires is benign — clearing a field that was already empty never
    /// changes anything to observe — so this is pure added latency there.
    private static let clearSettleTimeout: TimeInterval = 0.6

    /// How long to wait for the insertion to show up in the tree before calling it
    /// a no-op. Long enough for a loaded device to commit a paste, short enough
    /// that a genuinely dead keyboard fails fast.
    private static let effectTimeout: TimeInterval = 1.5
    private static let effectPollInterval: TimeInterval = 0.15
}
