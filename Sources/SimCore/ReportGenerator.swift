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
// The reports remain self-contained HTML with inline CSS/JS and Base64-embedded
// screenshots, and verify status is still auto-detected from findings.json.
// What a reader gets out of them is tuned for reading, not just for existing:
// every step card names the action it captured and how its verify checks landed,
// failing tests sort to the top, the light/dark screenshots sit side by side at a
// size where a difference is actually visible, the lightbox walks a row or a test
// with the arrow keys, and both reports follow the reader's colour scheme with a
// toggle for when they want the other one.
//
// Screenshots are re-encoded through ImageIO down to `thumbnailMaxPixel` on the
// long side before embedding: a device-native capture is several times larger
// than any on-screen presentation of it, and Base64 inflates whatever it is
// handed by a third. Foundation + ImageIO only: no SimBridge, no Process(), no
// private frameworks, still unit-testable.

import Foundation
import CoreGraphics
import ImageIO

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

    /// Long-side ceiling for an embedded screenshot. Both reports show captures
    /// as ~200px thumbnails, and the lightbox shows these bytes at their own size
    /// rather than stretching them.
    ///
    /// It bounds the LONG side, which is not the same as covering a 200px
    /// thumbnail at 2x: measured on real captures, a portrait phone lands at
    /// 276x600 — short of the 400px a 200px cell wants — while an iPad lands at
    /// 450x600 and clears it. That is the deliberate trade. On a 28-capture verify
    /// directory the report is 17MB at native size, 11MB at 1800px, 6.8MB at
    /// 1200px, and 2.4MB here; the grid is for scanning and the lightbox is where
    /// a capture gets looked at.
    ///
    /// It is a target, not a guarantee: `downscaledPNG` refuses a re-encode that
    /// comes out no smaller than the original, and that capture is embedded at its
    /// own size. Real screenshots compress well enough that this does not happen;
    /// a synthetic image whose structure PNG predicts almost exactly does hit it.
    static let thumbnailMaxPixel = 600

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

    /// Re-encode `data` as a PNG whose longest side is at most `maxPixel`.
    /// Returns nil when the image cannot be read, is already within the limit,
    /// or the re-encode did not actually come out smaller — every one of those
    /// cases means the caller should embed the original bytes.
    static func downscaledPNG(_ data: Data, maxPixel: Int = thumbnailMaxPixel) -> Data? {
        guard maxPixel > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              max(width, height) > maxPixel else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, thumb, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        let shrunk = out as Data
        return shrunk.count < data.count ? shrunk : nil
    }

    private static func imageDataURI(_ path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let bytes = downscaledPNG(data) ?? data
        return "data:image/png;base64," + bytes.base64EncodedString()
    }

    private static let darkTokens = """
    --bg:#1c1c1e;--fg:#f2f2f7;--card:#2c2c2e;--muted:#98989d;--line:#3a3a3c;
    --line-soft:#323234;--head:#242426;--hover:#333335;--accent:#0a84ff;
    --pass-bg:#1d3a26;--pass-fg:#7ee2a0;--fail-bg:#4a1f25;--fail-fg:#ff9aa5;
    --review-bg:#453718;--review-fg:#ffd479;--skip-bg:#3a3a3c;--skip-fg:#c7c7cc;
    --fail-edge:#ff453a;--review-edge:#ffd60a;--found:#30d158;--missing:#ff453a;
    --shadow:0 1px 3px rgba(0,0,0,0.45)
    """

    /// Shared design tokens, in the three states a reader can be in: no choice
    /// made (follow the system), an explicit dark choice, an explicit light one.
    /// The dark tokens are therefore emitted twice — once behind the media query
    /// (skipped when the reader has explicitly chosen light) and once behind the
    /// attribute the toggle sets, so the button wins in both directions.
    private static let paletteCSS = """
    :root{--bg:#f5f5f7;--fg:#1d1d1f;--card:#ffffff;--muted:#86868b;--line:#e5e5e5;
    --line-soft:#f0f0f0;--head:#f5f5f7;--hover:#fafafa;--accent:#007aff;
    --pass-bg:#d4edda;--pass-fg:#155724;--fail-bg:#f8d7da;--fail-fg:#721c24;
    --review-bg:#fff3cd;--review-fg:#856404;--skip-bg:#e2e3e5;--skip-fg:#6c757d;
    --fail-edge:#dc3545;--review-edge:#ffc107;--found:#28a745;--missing:#dc3545;
    --shadow:0 1px 3px rgba(0,0,0,0.08)}
    @media (prefers-color-scheme:dark){:root:not([data-theme="light"]){\(darkTokens)}}
    :root[data-theme="dark"]{\(darkTokens)}
    *{margin:0;padding:0;box-sizing:border-box}
    body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:var(--bg);color:var(--fg);padding:24px}
    .page-head{display:flex;align-items:flex-start;gap:16px;margin-bottom:4px}
    .page-head h1{flex:1;margin-bottom:0}
    .theme-toggle{flex:0 0 auto;border:1px solid var(--line);background:var(--card);color:var(--fg);
    border-radius:16px;padding:6px 13px;font:inherit;font-size:12px;font-weight:600;cursor:pointer;
    box-shadow:var(--shadow);white-space:nowrap}
    .theme-toggle:hover{background:var(--hover)}
    @media print{.theme-toggle{display:none}}
    """

    /// Applied in `<head>`, before the body paints, so a reader who chose dark
    /// last time does not get a white flash first.
    private static let themeBootScript = """
    try{var t=localStorage.getItem('sipi-report-theme');
    if(t==='dark'||t==='light')document.documentElement.setAttribute('data-theme',t);}catch(e){}
    """

    private static let themeToggleHTML =
        "<button class=\"theme-toggle\" id=\"theme-toggle\" onclick=\"toggleTheme()\">&#9789; Dark</button>"

    private static let themeJS = """
    function currentTheme(){var t=document.documentElement.getAttribute('data-theme');
    if(t==='dark'||t==='light')return t;
    return window.matchMedia&&window.matchMedia('(prefers-color-scheme:dark)').matches?'dark':'light';}
    function syncThemeToggle(){var b=document.getElementById('theme-toggle');if(!b)return;
    b.innerHTML=currentTheme()==='dark'?'\\u263C Light':'\\u263D Dark';}
    function toggleTheme(){var next=currentTheme()==='dark'?'light':'dark';
    document.documentElement.setAttribute('data-theme',next);
    try{localStorage.setItem('sipi-report-theme',next);}catch(e){}
    syncThemeToggle();}
    syncThemeToggle();
    if(window.matchMedia){var mq=window.matchMedia('(prefers-color-scheme:dark)');
    if(mq.addEventListener)mq.addEventListener('change',syncThemeToggle);}
    """

    /// Shared lightbox chrome. The group a thumbnail belongs to is whatever
    /// ancestor carries `data-lightbox-group` — a test's step strip, or one row
    /// of the verify grid — so the arrow keys walk exactly the set the reader
    /// was already comparing.
    private static let lightboxCSS = """
    .lightbox{display:none;position:fixed;inset:0;background:rgba(0,0,0,0.85);z-index:100;
    justify-content:center;align-items:center;gap:8px;cursor:zoom-out}
    .lightbox.active{display:flex}
    .lightbox figure{display:flex;flex-direction:column;align-items:center;gap:10px;cursor:default}
    .lightbox img{max-width:82vw;max-height:86vh;border-radius:8px;background:#fff}
    .lightbox figcaption{color:#f5f5f7;font-size:13px;text-align:center;max-width:82vw}
    .lb-nav{flex:0 0 auto;width:44px;height:44px;border:0;border-radius:22px;cursor:pointer;
    background:rgba(255,255,255,0.14);color:#fff;font-size:26px;line-height:1}
    .lb-nav:hover{background:rgba(255,255,255,0.26)}
    """

    private static let lightboxHTML = """
    <div class="lightbox" id="lightbox" onclick="closeLightbox()">
    <button class="lb-nav" onclick="event.stopPropagation();moveLightbox(-1)" aria-label="Previous">&lsaquo;</button>
    <figure onclick="event.stopPropagation()"><img id="lightbox-img" src="" alt=""><figcaption id="lightbox-cap"></figcaption></figure>
    <button class="lb-nav" onclick="event.stopPropagation();moveLightbox(1)" aria-label="Next">&rsaquo;</button>
    </div>
    """

    /// Note the `lightboxOpen()` guard on the key handler: without it a closed
    /// lightbox still owns the arrow keys, so scrolling the page after pressing
    /// Escape re-opened the last image instead of scrolling.
    private static let lightboxJS = """
    var lbGroup=[],lbIndex=0;
    function lightboxEl(){return document.getElementById('lightbox');}
    function lightboxOpen(){return lightboxEl().classList.contains('active');}
    function openLightbox(el){if(!el)return;
    var g=el.closest('[data-lightbox-group]');
    lbGroup=g?Array.prototype.slice.call(g.querySelectorAll('img[data-cap]')):[el];
    lbIndex=lbGroup.indexOf(el);if(lbIndex<0){lbGroup=[el];lbIndex=0;}
    renderLightbox();}
    function renderLightbox(){var el=lbGroup[lbIndex];if(!el)return;
    document.getElementById('lightbox-img').src=el.src;
    document.getElementById('lightbox-cap').textContent=el.getAttribute('data-cap')||'';
    lightboxEl().classList.add('active');}
    function moveLightbox(d){if(!lightboxOpen()||lbGroup.length<2)return;
    lbIndex=(lbIndex+d+lbGroup.length)%lbGroup.length;renderLightbox();}
    function closeLightbox(){lightboxEl().classList.remove('active');}
    document.addEventListener('keydown',function(e){
    if(!lightboxOpen())return;
    if(e.key==='Escape'){closeLightbox();}
    else if(e.key==='ArrowRight'){e.preventDefault();moveLightbox(1);}
    else if(e.key==='ArrowLeft'){e.preventDefault();moveLightbox(-1);}});
    """

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

        // Detail sections lead with what went wrong: failures, then anything
        // flagged for review, then the passes. Reading order inside each bucket
        // stays run order. Built before the table so the table only links to
        // tests that actually rendered a section to jump to.
        var details = ""
        var failureHighlights = ""
        var anchored: Set<String> = []
        for entry in tests.enumerated().sorted(by: { detailRank($0.element) < detailRank($1.element) }).map(\.element) {
            let tid = entry["id"] as? String ?? ""
            let b = badge(entry)
            let result = results[tid] ?? [:]
            let steps = result["steps"] as? [JSON] ?? []

            var stepsHTML = ""
            var failedHTML = ""
            for (i, step) in steps.enumerated() {
                let n = i + 1
                let ss = step["screenshot"] as? String ?? ""
                let action = step["action"] as? String ?? "(verify-only)"
                let checks = step["verify"] as? [Any] ?? []

                if !ss.isEmpty {
                    let cardCls = !((step["passed"] as? Bool) ?? false) ? "fail" : ((step["review"] as? Bool ?? false) ? "review" : "")
                    let imgPath = runDir + "/" + safeRelpath(tid) + "/" + safeRelpath(ss)
                    let sdur = (step["duration"] as? Double).map { String(format: "%.1f", $0) + "s" } ?? ""
                    let caption = esc("\(tid) · step \(n): \(action)")
                    stepsHTML += "<div class=\"step-card \(cardCls)\" onclick=\"openLightbox(this.querySelector('img'))\">"
                    if let dataURI = imageDataURI(imgPath) {
                        stepsHTML += "<img src=\"\(dataURI)\" alt=\"Step \(n)\" data-cap=\"\(caption)\">"
                    } else {
                        let imgSrc = "\(safeRelpath(tid))/\(safeRelpath(ss))"
                        stepsHTML += "<img src=\"\(esc(imgSrc))\" alt=\"Step \(n)\" data-cap=\"\(caption)\">"
                    }
                    stepsHTML += "<div class=\"step-label\">"
                    stepsHTML += "<div class=\"step-head\"><span class=\"step-n\">\(n)</span>"
                    stepsHTML += "<span class=\"step-dur\">\(sdur)</span>\(verifyTally(checks))</div>"
                    stepsHTML += "<div class=\"step-action\" title=\"\(esc(action))\">\(esc(action))</div>"
                    stepsHTML += "</div></div>\n"
                }

                if !((step["passed"] as? Bool) ?? false) {
                    let ft = esc(step["failure-type"] as? String ?? "")
                    let renderedChecks = renderVerify(checks)
                    let methods = renderMethods(step["attempted-methods"] as? [Any] ?? [])
                    let snapshot = esc(step["describe-ui-snapshot"] as? String ?? "")
                    let missing = esc(firstMissingVerify(checks) ?? "")
                    failureHighlights += "<div class=\"failure-card\"><div><span class=\"badge badge-fail\">FAIL</span> <strong>\(esc(tid))</strong> step \(n)</div>"
                    failureHighlights += "<p>\(esc(action))</p>"
                    if !ft.isEmpty { failureHighlights += "<dl><dt>Failure Type</dt><dd>\(ft)</dd></dl>" }
                    if !missing.isEmpty { failureHighlights += "<dl><dt>Missing Verify</dt><dd>\(missing)</dd></dl>" }
                    if !methods.isEmpty { failureHighlights += "<dl><dt>Attempted Methods</dt><dd>\(methods)</dd></dl>" }
                    failureHighlights += "</div>\n"
                    failedHTML += "<div class=\"step-info\"><h4>Step \(n): \(esc(action))</h4><dl>"
                    failedHTML += "<dt>Failure Type</dt><dd>\(ft)</dd>"
                    failedHTML += "<dt>Verify</dt><dd>\(renderedChecks)</dd>"
                    failedHTML += "<dt>Attempted Methods</dt><dd>\(methods)</dd></dl>"
                    failedHTML += "<details><summary>describe-ui snapshot</summary><pre>\(snapshot)</pre></details></div>\n"
                }
            }
            if stepsHTML.isEmpty && failedHTML.isEmpty { continue }
            anchored.insert(tid)

            details += "<div class=\"detail\" id=\"test-\(esc(slug(tid)))\">"
            details += "<h3><span class=\"badge \(b.cls)\">\(b.label)</span> \(esc(tid))</h3>"
            if !stepsHTML.isEmpty {
                details += "<div class=\"steps\" data-lightbox-group>\(stepsHTML)</div>"
            }
            if !failedHTML.isEmpty {
                details += failedHTML
            }
            details += "</div>\n"
        }

        // The table is the index of the run, so it keeps run order. A test links
        // to its detail section only when one exists: a test with no screenshots
        // and nothing failed renders no section, and a link to it would go
        // nowhere.
        var tableRows = ""
        for entry in tests {
            let tid = entry["id"] as? String ?? ""
            let b = badge(entry)
            let dur = entry["duration"] as? Double ?? 0
            let result = results[tid] ?? [:]
            let steps = result["steps"] as? [JSON] ?? []
            let notes = steps.compactMap { $0["note"] as? String }.joined(separator: "; ")
            let name = anchored.contains(tid)
                ? "<a href=\"#test-\(esc(slug(tid)))\">\(esc(tid))</a>"
                : esc(tid)
            tableRows += "<tr><td><span class=\"badge \(b.cls)\">\(b.label)</span></td>"
            tableRows += "<td>\(name)</td>"
            tableRows += "<td>\(String(format: "%.1f", dur))s</td>"
            tableRows += "<td class=\"note\">\(esc(notes))</td></tr>\n"
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

        let failureSection = failureHighlights.isEmpty
            ? ""
            : "<section class=\"failures\"><h2>Failure Highlights</h2>\(failureHighlights)</section>"

        let css = paletteCSS + """
        h1{font-size:24px;font-weight:600;margin-bottom:4px}
        h2{font-size:18px;font-weight:600;margin-bottom:12px}
        .meta{color:var(--muted);font-size:14px;margin-bottom:16px}
        .summary{display:flex;gap:16px;margin-bottom:24px;flex-wrap:wrap}
        .summary-item{padding:8px 16px;border-radius:10px;font-size:14px;font-weight:600}
        .summary-pass{background:var(--pass-bg);color:var(--pass-fg)}
        .summary-fail{background:var(--fail-bg);color:var(--fail-fg)}
        .summary-review{background:var(--review-bg);color:var(--review-fg)}
        .summary-total{background:var(--skip-bg);color:var(--skip-fg)}
        .failures{background:var(--card);border-left:4px solid var(--fail-edge);border-radius:8px;padding:16px;margin-bottom:24px;box-shadow:var(--shadow)}
        .failure-card{border-top:1px solid var(--line-soft);padding:12px 0;font-size:13px;line-height:1.5}
        .failure-card:first-of-type{border-top:0;padding-top:0}.failure-card p{margin-top:6px}
        .failure-card dl{display:grid;grid-template-columns:120px 1fr;gap:4px 10px;margin-top:6px}
        .failure-card dt{color:var(--muted);font-weight:600}.failure-card dd{margin:0}
        table{width:100%;border-collapse:collapse;background:var(--card);border-radius:12px;overflow:hidden;box-shadow:var(--shadow);margin-bottom:24px}
        thead th{background:var(--head);padding:12px 16px;font-size:13px;font-weight:600;text-align:left;border-bottom:1px solid var(--line)}
        tbody td{padding:10px 16px;border-bottom:1px solid var(--line-soft);font-size:14px;vertical-align:middle}
        tbody tr:hover{background:var(--hover)}
        tbody td a{color:var(--accent);text-decoration:none}tbody td a:hover{text-decoration:underline}
        .badge{display:inline-block;padding:2px 10px;border-radius:12px;font-size:12px;font-weight:600}
        .badge-pass{background:var(--pass-bg);color:var(--pass-fg)}
        .badge-fail{background:var(--fail-bg);color:var(--fail-fg)}
        .badge-review{background:var(--review-bg);color:var(--review-fg)}
        .badge-skip{background:var(--skip-bg);color:var(--skip-fg)}
        .detail{background:var(--card);border-radius:12px;padding:20px;margin-bottom:16px;box-shadow:var(--shadow);scroll-margin-top:16px}
        .detail h3{font-size:16px;margin-bottom:12px}
        .steps{display:flex;gap:12px;overflow-x:auto;padding:8px 0}
        .step-card{flex:0 0 200px;border:1px solid var(--line);border-radius:10px;overflow:hidden;cursor:pointer;transition:transform 0.15s;background:var(--card)}
        .step-card:hover{transform:translateY(-2px);box-shadow:0 4px 8px rgba(0,0,0,0.1)}
        .step-card.fail{border-color:var(--fail-edge)}.step-card.review{border-color:var(--review-edge)}
        .step-card img{width:100%;aspect-ratio:9/19.5;object-fit:cover;object-position:top;background:var(--head)}
        .step-label{padding:6px 10px 8px;font-size:12px;border-top:1px solid var(--line-soft)}
        .step-head{display:flex;align-items:center;gap:6px;font-weight:600}
        .step-n{background:var(--skip-bg);color:var(--skip-fg);border-radius:6px;padding:0 6px}
        .step-dur{color:var(--muted);font-weight:500;margin-left:auto}
        .tally{font-weight:600;font-variant-numeric:tabular-nums}
        .tally-ok{color:var(--found)}.tally-bad{color:var(--missing)}
        .step-action{margin-top:4px;color:var(--muted);line-height:1.35;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;
        font-size:11px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
        .step-info{margin-top:12px;font-size:13px;line-height:1.6}
        .step-info dt{font-weight:600;color:var(--muted);margin-top:8px}.step-info dd{margin-left:0}
        .verify-check{display:flex;gap:6px;align-items:center}
        .verify-check .found{color:var(--found)}.verify-check .not-found{color:var(--missing)}
        pre{background:var(--head);padding:12px;border-radius:8px;font-size:12px;overflow-x:auto;max-height:300px;overflow-y:auto;margin-top:8px}
        details{margin-top:8px}details summary{cursor:pointer;font-size:13px;color:var(--accent)}
        .note{font-size:12px;color:var(--muted)}
        """ + lightboxCSS

        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
        <title>Test Run: \(suiteName)</title><style>\(css)</style>
        <script>\(themeBootScript)</script></head>
        <body>
        <header class="page-head"><h1>\(suiteName)</h1>\(themeToggleHTML)</header>
        <p class="meta">\(deviceName) &middot; \(deviceRuntime) &middot; \(commit) &middot; \(started)</p>
        <div class="summary">\(summaryHTML)</div>
        \(failureSection)
        <table><thead><tr><th>Status</th><th>Test</th><th>Duration</th><th>Notes</th></tr></thead>
        <tbody>\(tableRows)</tbody></table>
        \(details)
        \(lightboxHTML)
        <script>\(themeJS)\(lightboxJS)</script>
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
        try writeTestRunSummary(runDir: runDir)
        return outPath
    }

    /// Build the compact machine-readable summary for a test run. This is meant
    /// for agents and CI so they do not need to scrape the heavier HTML report.
    public static func testRunSummary(runDir: String) throws -> [String: Any] {
        guard let run = loadJSON(runDir + "/run.json") else {
            throw ReportError("\(runDir)/run.json: not found or invalid")
        }

        let tests = run["tests"] as? [JSON] ?? []
        let summary = run["summary"] as? JSON ?? [:]
        let total = summary["total"] as? Int ?? tests.count
        let passed = summary["passed"] as? Int ?? tests.filter { $0["passed"] as? Bool == true }.count
        let failed = summary["failed"] as? Int ?? tests.filter { $0["passed"] as? Bool == false }.count
        let review = summary["review"] as? Int ?? tests.filter { $0["review"] as? Bool == true }.count
        let skipped = tests.filter { $0["skipped"] as? Bool == true }.count
        let status: String
        if failed > 0 {
            status = "fail"
        } else if review > 0 {
            status = "review"
        } else if total == 0 {
            status = "empty"
        } else {
            status = "pass"
        }

        var topFailures: [[String: Any]] = []
        for entry in tests {
            guard entry["passed"] as? Bool == false,
                  let tid = entry["id"] as? String,
                  !tid.contains(".."), !tid.contains("/") else { continue }
            let resultPath = runDir + "/" + tid + "/result.json"
            guard let result = loadJSON(resultPath),
                  let steps = result["steps"] as? [JSON] else { continue }
            for (index, step) in steps.enumerated() where step["passed"] as? Bool == false {
                var failure: [String: Any] = [
                    "test": tid,
                    "step": index + 1,
                    "failure-type": step["failure-type"] as? String ?? "",
                    "action": step["action"] as? String ?? "(verify-only)"
                ]
                if let verify = step["verify"] as? [Any] {
                    if let missing = firstMissingVerify(verify) {
                        failure["missing"] = missing
                        failure["verify"] = missing
                    }
                    if let matched = firstMatchedVerify(verify) {
                        failure["matched"] = matched
                    }
                }
                if let screenshot = step["screenshot"] as? String {
                    failure["screenshot"] = tid + "/" + screenshot
                }
                topFailures.append(failure)
                break
            }
        }

        return [
            "status": status,
            "run-id": URL(fileURLWithPath: runDir).lastPathComponent,
            "started": run["started"] as? String ?? "",
            "finished": run["finished"] as? String ?? "",
            "device": [
                "name": run["device-name"] as? String ?? "",
                "runtime": run["device-runtime"] as? String ?? "",
                "udid": run["device"] as? String ?? ""
            ],
            "counts": [
                "total": total,
                "passed": passed,
                "failed": failed,
                "review": review,
                "skipped": skipped
            ],
            "top-failures": topFailures,
            "report": "report.html"
        ]
    }

    /// Write `<runDir>/summary.json` and return its path.
    @discardableResult
    public static func writeTestRunSummary(runDir: String) throws -> String {
        let summary = try testRunSummary(runDir: runDir)
        let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
        let outPath = runDir + "/summary.json"
        do {
            try data.write(to: URL(fileURLWithPath: outPath))
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

    /// Failures first, then review, then everything else.
    private static func detailRank(_ entry: JSON) -> Int {
        if !((entry["passed"] as? Bool) ?? false) { return 0 }
        if (entry["review"] as? Bool) ?? false { return 1 }
        return 2
    }

    /// A stable HTML id for a test, so the run table can link into its detail.
    private static func slug(_ id: String) -> String {
        let allowed = id.map { ch -> Character in
            ch.isLetter || ch.isNumber ? Character(ch.lowercased()) : "-"
        }
        return String(allowed)
    }

    /// `✓2/2` when a step carried verify checks, empty when it carried none.
    /// A step whose screenshot is the only record of what happened reads as one
    /// more picture; a step that asserted something reads as an assertion.
    private static func verifyTally(_ checks: [Any]) -> String {
        let objects = checks.compactMap { $0 as? JSON }
        guard !objects.isEmpty else { return "" }
        let found = objects.filter { ($0["found"] as? Bool) ?? false }.count
        let cls = found == objects.count ? "tally-ok" : "tally-bad"
        let icon = found == objects.count ? "✓" : "✗"
        return "<span class=\"tally \(cls)\">\(icon)\(found)/\(objects.count)</span>"
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

    private static func firstMissingVerify(_ checks: [Any]) -> String? {
        for item in checks {
            guard let verify = item as? JSON else { continue }
            if verify["found"] as? Bool == false {
                return verify["check"] as? String
            }
        }
        return nil
    }

    private static func firstMatchedVerify(_ checks: [Any]) -> String? {
        for item in checks {
            guard let verify = item as? JSON else { continue }
            if verify["found"] as? Bool == true {
                return verify["grep-match"] as? String ?? verify["check"] as? String
            }
        }
        return nil
    }

    private static func renderMethods(_ methods: [Any]) -> String {
        methods.compactMap { $0 as? JSON }.map { m in
            let method = m["method"] as? String ?? "?"
            let value = esc(m["value"] as? String ?? "")
            return "\(method)(\(value))"
        }.joined(separator: ", ")
    }

    // MARK: - Verify report (formerly generate_verify_report.swift)

    /// The capture matrix, split into its two axes so the header can group the
    /// appearance columns under their device. Light and dark end up adjacent —
    /// the comparison a reader actually makes — and one check stays one row.
    private static let verifyDevices: [(key: String, label: String)] = [
        ("iphone", "iPhone"), ("ipad", "iPad")
    ]
    private static let verifyModes: [(key: String, label: String)] = [
        ("light", "Light"), ("dark", "Dark")
    ]
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
        let findingsHTML = renderFindingsHTML(findingsPath: findingsPath)

        // One row per check, with every capture of it on that row: light and dark
        // stay adjacent under their own device, and one row is one comparison the
        // arrow keys can walk end to end. A device with no captures anywhere in
        // the session drops out instead of rendering a column of N/A.
        let activeDevices = verifyDevices.filter { device in
            checks.contains { check in
                verifyModes.contains { check.variants["\(device.key)-\($0.key)"] != nil }
            }
        }

        var rows = ""
        for check in checks {
            rows += "<tr data-lightbox-group><td class=\"rowhead\">\(esc(check.description))</td>"
            for device in activeDevices {
                for (index, mode) in verifyModes.enumerated() {
                    let edge = index == 0 ? " devstart" : ""
                    let variant = "\(device.key)-\(mode.key)"
                    guard let fname = check.variants[variant],
                          let dataURI = imageDataURI(verifyDir + "/" + variant + "/" + fname) else {
                        rows += "<td class=\"absent\(edge)\">N/A</td>"
                        continue
                    }
                    let caption = esc("\(check.description) · \(device.label) \(mode.label)")
                    rows += "<td class=\"shot\(edge)\"><img src=\"\(dataURI)\" alt=\"\(esc(variant))\""
                    rows += " data-cap=\"\(caption)\" onclick=\"openLightbox(this)\"></td>"
                }
            }
            rows += "</tr>\n"
        }

        let dirName = esc(URL(fileURLWithPath: verifyDir).lastPathComponent)

        let css = paletteCSS + """
        h1{font-size:24px;font-weight:600;margin-bottom:4px}
        .meta{color:var(--muted);font-size:14px;margin-bottom:24px}
        .status{display:inline-block;padding:2px 10px;border-radius:12px;font-size:13px;font-weight:500;margin-left:8px}
        .status-ok{background:var(--pass-bg);color:var(--pass-fg)}
        .status-issue{background:var(--fail-bg);color:var(--fail-fg)}
        .findings{background:var(--card);border-radius:8px;padding:16px;margin-bottom:20px;box-shadow:var(--shadow)}
        .findings h2{font-size:17px;margin-bottom:10px}.findings ul{padding-left:20px}
        .findings li{margin:6px 0;font-size:14px;line-height:1.4}
        .findings .empty{color:var(--pass-fg)}.findings .warn{color:var(--fail-fg)}
        table{width:auto;border-collapse:collapse;background:var(--card);border-radius:12px;overflow:hidden;box-shadow:var(--shadow)}
        thead th{background:var(--head);padding:10px 8px;font-size:13px;font-weight:600;text-align:center;border-bottom:1px solid var(--line)}
        thead tr:first-child th{padding-top:12px}
        thead tr:first-child th:not(:first-child){border-bottom:1px solid var(--line-soft);color:var(--muted)}
        thead th:first-child{text-align:left;padding-left:16px;width:200px;vertical-align:bottom}
        thead tr:last-child th{width:220px}
        tbody td{padding:10px 8px;vertical-align:top;border-bottom:1px solid var(--line-soft);text-align:center}
        tbody td.rowhead{font-size:14px;font-weight:500;padding-left:16px;text-align:left}
        tbody td.absent{color:var(--muted);font-size:13px}
        th.devstart,td.devstart{border-left:1px solid var(--line)}
        tbody td img{width:100%;max-width:200px;height:auto;display:block;margin:0 auto;border-radius:8px;cursor:pointer;transition:transform 0.2s;background:var(--head)}
        tbody td img:hover{transform:scale(1.02)}
        """ + lightboxCSS

        var deviceHead = "<th rowspan=\"2\">Check</th>"
        var modeHead = ""
        for device in activeDevices {
            deviceHead += "<th colspan=\"\(verifyModes.count)\" class=\"devstart\">\(esc(device.label))</th>"
            for (index, mode) in verifyModes.enumerated() {
                modeHead += index == 0
                    ? "<th class=\"devstart\">\(mode.label)</th>"
                    : "<th>\(mode.label)</th>"
            }
        }

        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
        <title>Verify: \(esc(title))</title><style>\(css)</style>
        <script>\(themeBootScript)</script></head>
        <body>
        <header class="page-head">
        <h1>\(esc(title)) <span class="status \(statusClass)">\(statusLabel)</span></h1>
        \(themeToggleHTML)</header>
        <p class="meta">\(dirName)</p>
        \(findingsHTML)
        <table><thead><tr>\(deviceHead)</tr><tr>\(modeHead)</tr></thead>
        <tbody>\(rows)</tbody></table>
        \(lightboxHTML)
        <script>\(themeJS)\(lightboxJS)</script>
        </body></html>
        """

        return html
    }

    private static func renderFindingsHTML(findingsPath: String) -> String {
        guard FileManager.default.fileExists(atPath: findingsPath) else {
            return "<section class=\"findings\"><h2>Findings</h2><p class=\"warn\">findings.json is missing; status is fail-safe.</p></section>"
        }
        guard let data = FileManager.default.contents(atPath: findingsPath),
              let parsed = try? JSONSerialization.jsonObject(with: data),
              let findings = parsed as? [[String: Any]] else {
            return "<section class=\"findings\"><h2>Findings</h2><p class=\"warn\">findings.json is invalid; status is fail-safe.</p></section>"
        }
        if findings.isEmpty {
            return "<section class=\"findings\"><h2>Findings</h2><p class=\"empty\">No findings recorded.</p></section>"
        }
        let items = findings.map { finding -> String in
            let check = esc(finding["check"] as? String ?? "finding")
            let variant = esc(finding["variant"] as? String ?? "all variants")
            let issue = esc(finding["issue"] as? String ?? "")
            return "<li><strong>\(check)</strong> <span>\(variant)</span>: \(issue)</li>"
        }.joined()
        return "<section class=\"findings\"><h2>Findings</h2><ul>\(items)</ul></section>"
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
