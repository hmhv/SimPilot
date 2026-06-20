// ReportGenerator.swift
//
// HTML report generation for SimPilot test runs and verification directories.
//
// This is the in-binary home of what used to be the loose interpreter scripts
// generate_test_report.swift / generate_verify_report.swift under the skill
// trees. Folding them into the sipi binary keeps the curl|bash install a single
// self-contained download (no `swift` interpreter invocation on the user
// machine, no $SKILL_ROOT script resolution). The skill docs now call
// `sipi report` / `sipi verify-report`.
//
// Output shape is preserved byte-for-byte from the original scripts: the same
// HTML structure, inline CSS/JS, Base64 PNG embedding, verify-status
// auto-detection from findings.json, and the verify thumbnail max-width:220px
// sizing fix. Pure Foundation — no SimBridge, no Process(), unit-testable.

import Foundation

/// Generates self-contained HTML reports (test run and verification) for a
/// SimPilot workspace. Mirrors the original standalone report scripts.
public enum ReportGenerator {

    /// A simple message-only error surfaced to the CLI for report failures.
    public struct ReportError: Error, CustomStringConvertible {
        public let message: String
        public init(_ message: String) { self.message = message }
        public var description: String { message }
    }

    private typealias JSON = [String: Any]

    // MARK: - Shared helpers

    private static func loadJSON(_ path: String) -> JSON? {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? JSON else { return nil }
        return json
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func safeRelpath(_ name: String) -> String {
        if name.hasPrefix("/") || name.contains("..") { return "invalid" }
        return name
    }

    private static func imageDataURI(_ path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return "data:image/png;base64," + data.base64EncodedString()
    }

    // MARK: - Test run report (formerly generate_test_report.swift)

    /// Build the test-run report HTML for `runDir`, reading `run.json` and each
    /// per-test `result.json`. Returns the full HTML document. Throws
    /// ReportError if `run.json` is missing or invalid.
    public static func testReportHTML(runDir: String) throws -> String {
        guard let run = loadJSON(runDir + "/run.json") else {
            throw ReportError("\(runDir)/run.json: not found or invalid")
        }

        let suiteName = esc(run["suite"] as? String ?? "Ad-hoc Run")
        let deviceName = esc(run["device-name"] as? String ?? "")
        let deviceRuntime = esc(run["device-runtime"] as? String ?? "")
        let commit = esc(run["commit"] as? String ?? "")
        let started = esc(run["started"] as? String ?? "")
        let summary = run["summary"] as? JSON ?? [:]
        let tests = run["tests"] as? [JSON] ?? []

        // Load results
        var results: [String: JSON] = [:]
        for entry in tests {
            guard let tid = entry["id"] as? String,
                  !tid.contains(".."), !tid.contains("/") else { continue }
            let resultPath = runDir + "/" + tid + "/result.json"
            if let r = loadJSON(resultPath) {
                results[tid] = r
            } else {
                FileHandle.standardError.write(Data(
                    "WARNING: \(resultPath): missing or invalid result.json for test '\(tid)'\n".utf8))
            }
        }

        // Table rows
        var tableRows = ""
        for entry in tests {
            let tid = entry["id"] as? String ?? ""
            let b = badge(entry)
            let dur = entry["duration"] as? Double ?? 0
            let result = results[tid] ?? [:]
            let steps = result["steps"] as? [JSON] ?? []
            let notes = steps.compactMap { $0["note"] as? String }.joined(separator: "; ")
            tableRows += "<tr><td><span class=\"badge \(b.cls)\">\(b.label)</span></td>"
            tableRows += "<td>\(esc(tid))</td><td>\(String(format: "%.1f", dur))s</td>"
            tableRows += "<td class=\"note\">\(esc(notes))</td></tr>\n"
        }

        // Detail sections
        var details = ""
        for entry in tests {
            let tid = entry["id"] as? String ?? ""
            let b = badge(entry)
            let result = results[tid] ?? [:]
            let steps = result["steps"] as? [JSON] ?? []

            var stepsHTML = ""
            var failedHTML = ""
            for (i, step) in steps.enumerated() {
                let n = i + 1
                let ss = step["screenshot"] as? String ?? ""
                if !ss.isEmpty {
                    // badge computed inline via cardCls below
                    let cardCls = !((step["passed"] as? Bool) ?? false) ? "fail" : ((step["review"] as? Bool ?? false) ? "review" : "")
                    let imgPath = runDir + "/" + safeRelpath(tid) + "/" + safeRelpath(ss)
                    let sdur = (step["duration"] as? Double).map { String(format: "%.1f", $0) + "s" } ?? ""
                    stepsHTML += "<div class=\"step-card \(cardCls)\" onclick=\"openLightbox(this.querySelector('img'))\">"
                    if let dataURI = imageDataURI(imgPath) {
                        stepsHTML += "<img src=\"\(dataURI)\" alt=\"Step \(n)\">"
                    } else {
                        let imgSrc = "\(safeRelpath(tid))/\(safeRelpath(ss))"
                        stepsHTML += "<img src=\"\(esc(imgSrc))\" alt=\"Step \(n)\">"
                    }
                    stepsHTML += "<div class=\"step-label\"><span>Step \(n)</span><span>\(sdur)</span></div></div>\n"
                }

                if !((step["passed"] as? Bool) ?? false) {
                    let action = esc(step["action"] as? String ?? "(verify-only)")
                    let ft = esc(step["failure-type"] as? String ?? "")
                    let checks = renderVerify(step["verify"] as? [Any] ?? [])
                    let methods = renderMethods(step["attempted-methods"] as? [Any] ?? [])
                    let snapshot = esc(step["describe-ui-snapshot"] as? String ?? "")
                    failedHTML += "<div class=\"step-info\"><h4>Step \(n): \(action)</h4><dl>"
                    failedHTML += "<dt>Failure Type</dt><dd>\(ft)</dd>"
                    failedHTML += "<dt>Verify</dt><dd>\(checks)</dd>"
                    failedHTML += "<dt>Attempted Methods</dt><dd>\(methods)</dd></dl>"
                    failedHTML += "<details><summary>describe-ui snapshot</summary><pre>\(snapshot)</pre></details></div>\n"
                }
            }
            if stepsHTML.isEmpty && failedHTML.isEmpty { continue }

            details += "<div class=\"detail\"><h3><span class=\"badge \(b.cls)\">\(b.label)</span> \(esc(tid))</h3>"
            if !stepsHTML.isEmpty {
                details += "<div class=\"steps\">\(stepsHTML)</div>"
            }
            if !failedHTML.isEmpty {
                details += failedHTML
            }
            details += "</div>\n"
        }

        // Summary
        let total = summary["total"] as? Int ?? 0
        let passed = summary["passed"] as? Int ?? 0
        let failed = summary["failed"] as? Int ?? 0
        let review = summary["review"] as? Int ?? 0
        var summaryHTML = "<span class=\"summary-item summary-total\">\(total) tests</span>"
        summaryHTML += "<span class=\"summary-item summary-pass\">\(passed) passed</span>"
        if review > 0 { summaryHTML += "<span class=\"summary-item summary-review\">\(review) review</span>" }
        if failed > 0 { summaryHTML += "<span class=\"summary-item summary-fail\">\(failed) failed</span>" }

        let css = """
        *{margin:0;padding:0;box-sizing:border-box}
        body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#f5f5f7;color:#1d1d1f;padding:24px}
        h1{font-size:24px;font-weight:600;margin-bottom:4px}
        .meta{color:#86868b;font-size:14px;margin-bottom:16px}
        .summary{display:flex;gap:16px;margin-bottom:24px;flex-wrap:wrap}
        .summary-item{padding:8px 16px;border-radius:10px;font-size:14px;font-weight:600}
        .summary-pass{background:#d4edda;color:#155724}.summary-fail{background:#f8d7da;color:#721c24}
        .summary-review{background:#fff3cd;color:#856404}.summary-total{background:#e2e3e5;color:#383d41}
        table{width:100%;border-collapse:collapse;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.08);margin-bottom:24px}
        thead th{background:#f5f5f7;padding:12px 16px;font-size:13px;font-weight:600;text-align:left;border-bottom:1px solid #e5e5e5}
        tbody td{padding:10px 16px;border-bottom:1px solid #f0f0f0;font-size:14px;vertical-align:middle}
        tbody tr:hover{background:#fafafa}
        .badge{display:inline-block;padding:2px 10px;border-radius:12px;font-size:12px;font-weight:600}
        .badge-pass{background:#d4edda;color:#155724}.badge-fail{background:#f8d7da;color:#721c24}
        .badge-review{background:#fff3cd;color:#856404}.badge-skip{background:#e2e3e5;color:#6c757d}
        .detail{background:#fff;border-radius:12px;padding:20px;margin-bottom:16px;box-shadow:0 1px 3px rgba(0,0,0,0.08)}
        .detail h3{font-size:16px;margin-bottom:12px}
        .steps{display:flex;gap:12px;overflow-x:auto;padding:8px 0}
        .step-card{flex:0 0 180px;border:1px solid #e5e5e5;border-radius:10px;overflow:hidden;cursor:pointer;transition:transform 0.15s}
        .step-card:hover{transform:translateY(-2px);box-shadow:0 4px 8px rgba(0,0,0,0.1)}
        .step-card.fail{border-color:#dc3545}.step-card.review{border-color:#ffc107}
        .step-card img{width:100%;aspect-ratio:9/19.5;object-fit:cover;background:#f0f0f0}
        .step-card .step-label{padding:6px 10px;font-size:12px;font-weight:500;display:flex;justify-content:space-between}
        .step-info{margin-top:12px;font-size:13px;line-height:1.6}
        .step-info dt{font-weight:600;color:#86868b;margin-top:8px}.step-info dd{margin-left:0}
        .verify-check{display:flex;gap:6px;align-items:center}
        .verify-check .found{color:#28a745}.verify-check .not-found{color:#dc3545}
        pre{background:#f5f5f7;padding:12px;border-radius:8px;font-size:12px;overflow-x:auto;max-height:300px;overflow-y:auto;margin-top:8px}
        details{margin-top:8px}details summary{cursor:pointer;font-size:13px;color:#007aff}
        .note{font-size:12px;color:#86868b}
        .lightbox{display:none;position:fixed;inset:0;background:rgba(0,0,0,0.85);z-index:100;justify-content:center;align-items:center;cursor:zoom-out}
        .lightbox.active{display:flex}.lightbox img{max-width:90vw;max-height:90vh;border-radius:8px}
        """

        let js = """
        function openLightbox(el){if(!el)return;document.getElementById('lightbox-img').src=el.src;document.getElementById('lightbox').classList.add('active');}
        function closeLightbox(){document.getElementById('lightbox').classList.remove('active');}
        document.addEventListener('keydown',e=>{if(e.key==='Escape')closeLightbox();});
        """

        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
        <title>Test Run: \(suiteName)</title><style>\(css)</style></head>
        <body>
        <h1>\(suiteName)</h1>
        <p class="meta">\(deviceName) &middot; \(deviceRuntime) &middot; \(commit) &middot; \(started)</p>
        <div class="summary">\(summaryHTML)</div>
        <table><thead><tr><th>Status</th><th>Test</th><th>Duration</th><th>Notes</th></tr></thead>
        <tbody>\(tableRows)</tbody></table>
        \(details)
        <div class="lightbox" id="lightbox" onclick="closeLightbox()"><img id="lightbox-img" src="" alt=""></div>
        <script>\(js)</script>
        </body></html>
        """

        return html
    }

    /// Generate the test-run report and write it to `<runDir>/report.html`.
    /// Returns the output path. Throws ReportError on read/write failure.
    @discardableResult
    public static func writeTestReport(runDir: String) throws -> String {
        let html = try testReportHTML(runDir: runDir)
        let outPath = runDir + "/report.html"
        do {
            try html.write(toFile: outPath, atomically: true, encoding: .utf8)
        } catch {
            throw ReportError("Failed to write \(outPath): \(error.localizedDescription)")
        }
        return outPath
    }

    private static func badge(_ entry: JSON) -> (cls: String, label: String) {
        let passed = entry["passed"] as? Bool ?? false
        let skipped = entry["skipped"] as? Bool ?? false
        let review = entry["review"] as? Bool ?? false
        if passed && skipped { return ("badge-skip", "SKIP") }
        if !passed { return ("badge-fail", "FAIL") }
        if review { return ("badge-review", "REVIEW") }
        return ("badge-pass", "PASS")
    }

    private static func renderVerify(_ checks: [Any]) -> String {
        checks.compactMap { $0 as? JSON }.map { v in
            let found = v["found"] as? Bool ?? false
            let cls = found ? "found" : "not-found"
            let icon = found ? "✓" : "✗"
            let check = esc(v["check"] as? String ?? "")
            return "<div class=\"verify-check\"><span class=\"\(cls)\">\(icon)</span> \(check)</div>"
        }.joined(separator: "\n")
    }

    private static func renderMethods(_ methods: [Any]) -> String {
        methods.compactMap { $0 as? JSON }.map { m in
            let method = m["method"] as? String ?? "?"
            let value = esc(m["value"] as? String ?? "")
            return "\(method)(\(value))"
        }.joined(separator: ", ")
    }

    // MARK: - Verify report (formerly generate_verify_report.swift)

    private static let verifyVariants = ["iphone-light", "iphone-dark", "ipad-light", "ipad-dark"]

    private struct VerifyCheck {
        let filename: String
        let description: String
        var variants: [String: String] // variant -> filename
    }

    private static func discoverChecks(_ verifyDir: String) -> [VerifyCheck] {
        let fm = FileManager.default
        var files: [String: [String: String]] = [:]
        for variant in verifyVariants {
            let vdir = verifyDir + "/" + variant
            guard let items = try? fm.contentsOfDirectory(atPath: vdir) else { continue }
            for item in items.sorted() where item.hasSuffix(".png") {
                files[item, default: [:]][variant] = item
            }
        }
        return files.keys.sorted().map { name in
            var desc = name
            if let range = name.range(of: "^\\d+_", options: .regularExpression) {
                desc = String(name[range.upperBound...])
            }
            if let dotRange = desc.range(of: ".", options: .backwards) {
                desc = String(desc[..<dotRange.lowerBound])
            }
            desc = desc.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
            return VerifyCheck(filename: name, description: desc, variants: files[name]!)
        }
    }

    /// Build the verify report HTML for `verifyDir`. `title` sets the page
    /// heading. `statusOverride` is a fallback ("ok"/"issue") used only when
    /// findings.json is absent; findings.json takes precedence (fail-safe to
    /// "issue"). Throws ReportError if `verifyDir` does not exist.
    public static func verifyReportHTML(
        verifyDir: String,
        title: String = "Verification",
        statusOverride: String? = nil
    ) throws -> String {
        guard FileManager.default.fileExists(atPath: verifyDir) else {
            throw ReportError("\(verifyDir): not found")
        }

        let checks = discoverChecks(verifyDir)

        // Auto-detect status from findings.json (fail-safe: default is "issue")
        let findingsPath = verifyDir + "/findings.json"
        var status = "issue" // fail-safe default
        let findingsFileExists = FileManager.default.fileExists(atPath: findingsPath)

        if findingsFileExists {
            if let findingsData = FileManager.default.contents(atPath: findingsPath),
               let parsed = try? JSONSerialization.jsonObject(with: findingsData) {
                if let findings = parsed as? [[String: Any]] {
                    // Valid array of objects
                    status = findings.isEmpty ? "ok" : "issue"
                    if let override = statusOverride, override == "ok" && !findings.isEmpty {
                        FileHandle.standardError.write(Data(
                            "WARNING: --status ok but findings.json contains \(findings.count) issue(s); using 'issue'\n".utf8))
                    } else if let override = statusOverride, override == "issue" && findings.isEmpty {
                        FileHandle.standardError.write(Data(
                            "NOTE: --status issue but findings.json is empty; using 'ok' per findings.json\n".utf8))
                    }
                } else {
                    // Valid JSON but wrong type (not array of objects)
                    FileHandle.standardError.write(Data(
                        "WARNING: findings.json exists but is not an array of objects; treating as 'issue'\n".utf8))
                    // status stays "issue" — --status ok cannot override a malformed file
                }
            } else {
                // File exists but is not valid JSON
                FileHandle.standardError.write(Data(
                    "WARNING: findings.json exists but contains invalid JSON; treating as 'issue'\n".utf8))
                // status stays "issue" — --status ok cannot override a malformed file
            }
        } else if let override = statusOverride {
            status = override
            if override == "ok" {
                FileHandle.standardError.write(Data(
                    "NOTE: --status ok without findings.json; status is caller-asserted (no independent verification)\n".utf8))
            }
        }
        // else: no findings.json, no flag → status stays "issue" (fail-safe)

        let statusClass = status == "ok" ? "status-ok" : "status-issue"
        let statusLabel = status == "ok" ? "All OK" : "Issues Found"

        var rows = ""
        for check in checks {
            rows += "<tr><td>\(esc(check.description))</td>"
            for variant in verifyVariants {
                if let fname = check.variants[variant] {
                    let imgPath = verifyDir + "/" + variant + "/" + fname
                    if let dataURI = imageDataURI(imgPath) {
                        rows += "<td><img src=\"\(dataURI)\" alt=\"\(esc(variant))\" onclick=\"openLightbox(this)\"></td>"
                    } else {
                        rows += "<td>N/A</td>"
                    }
                } else {
                    rows += "<td>N/A</td>"
                }
            }
            rows += "</tr>\n"
        }

        let dirName = esc(URL(fileURLWithPath: verifyDir).lastPathComponent)

        let css = """
        *{margin:0;padding:0;box-sizing:border-box}
        body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#f5f5f7;color:#1d1d1f;padding:24px}
        h1{font-size:24px;font-weight:600;margin-bottom:4px}
        .meta{color:#86868b;font-size:14px;margin-bottom:24px}
        .status{display:inline-block;padding:2px 10px;border-radius:12px;font-size:13px;font-weight:500;margin-left:8px}
        .status-ok{background:#d4edda;color:#155724}.status-issue{background:#f8d7da;color:#721c24}
        table{width:100%;border-collapse:collapse;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.08)}
        thead th{background:#f5f5f7;padding:12px 8px;font-size:13px;font-weight:600;text-align:center;border-bottom:1px solid #e5e5e5}
        thead th:first-child{text-align:left;padding-left:16px}
        tbody td{padding:8px;vertical-align:top;border-bottom:1px solid #f0f0f0}
        tbody td:first-child{font-size:14px;font-weight:500;padding-left:16px;min-width:160px}
        tbody td img{width:100%;max-width:220px;height:auto;display:block;margin:0 auto;border-radius:8px;cursor:pointer;transition:transform 0.2s}
        tbody td img:hover{transform:scale(1.02)}
        .lightbox{display:none;position:fixed;inset:0;background:rgba(0,0,0,0.85);z-index:100;justify-content:center;align-items:center;cursor:zoom-out}
        .lightbox.active{display:flex}.lightbox img{max-width:90vw;max-height:90vh;border-radius:8px}
        """

        let js = """
        function openLightbox(el){document.getElementById('lightbox-img').src=el.src;document.getElementById('lightbox').classList.add('active');}
        function closeLightbox(){document.getElementById('lightbox').classList.remove('active');}
        document.addEventListener('keydown',e=>{if(e.key==='Escape')closeLightbox();});
        """

        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
        <title>Verify: \(esc(title))</title><style>\(css)</style></head>
        <body>
        <h1>\(esc(title)) <span class="status \(statusClass)">\(statusLabel)</span></h1>
        <p class="meta">\(dirName)</p>
        <table><thead><tr><th>Check</th><th>iPhone Light</th><th>iPhone Dark</th><th>iPad Light</th><th>iPad Dark</th></tr></thead>
        <tbody>\(rows)</tbody></table>
        <div class="lightbox" id="lightbox" onclick="closeLightbox()"><img id="lightbox-img" src="" alt=""></div>
        <script>\(js)</script>
        </body></html>
        """

        return html
    }

    /// Generate the verify report and write it to `<verifyDir>/report.html`.
    /// Returns the output path. Throws ReportError on failure.
    @discardableResult
    public static func writeVerifyReport(
        verifyDir: String,
        title: String = "Verification",
        statusOverride: String? = nil
    ) throws -> String {
        let html = try verifyReportHTML(verifyDir: verifyDir, title: title, statusOverride: statusOverride)
        let outPath = verifyDir + "/report.html"
        do {
            try html.write(toFile: outPath, atomically: true, encoding: .utf8)
        } catch {
            throw ReportError("Failed to write \(outPath): \(error.localizedDescription)")
        }
        return outPath
    }
}
