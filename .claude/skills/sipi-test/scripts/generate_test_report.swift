#!/usr/bin/env swift
// generate_test_report.swift — Generate report.html for a test run directory.
// Usage: swift generate_test_report.swift <run-dir>

import Foundation

typealias JSON = [String: Any]

func loadJSON(_ path: String) -> JSON? {
    guard let data = FileManager.default.contents(atPath: path),
          let json = try? JSONSerialization.jsonObject(with: data) as? JSON else { return nil }
    return json
}

func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
     .replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;")
     .replacingOccurrences(of: "\"", with: "&quot;")
     .replacingOccurrences(of: "'", with: "&#39;")
}

func safeRelpath(_ name: String) -> String {
    if name.hasPrefix("/") || name.contains("..") { return "invalid" }
    return name
}

func badge(_ entry: JSON) -> (cls: String, label: String) {
    let passed = entry["passed"] as? Bool ?? false
    let skipped = entry["skipped"] as? Bool ?? false
    let review = entry["review"] as? Bool ?? false
    if passed && skipped { return ("badge-skip", "SKIP") }
    if !passed { return ("badge-fail", "FAIL") }
    if review { return ("badge-review", "REVIEW") }
    return ("badge-pass", "PASS")
}

func renderVerify(_ checks: [Any]) -> String {
    checks.compactMap { $0 as? JSON }.map { v in
        let found = v["found"] as? Bool ?? false
        let cls = found ? "found" : "not-found"
        let icon = found ? "✓" : "✗"
        let check = esc(v["check"] as? String ?? "")
        return "<div class=\"verify-check\"><span class=\"\(cls)\">\(icon)</span> \(check)</div>"
    }.joined(separator: "\n")
}

func renderMethods(_ methods: [Any]) -> String {
    methods.compactMap { $0 as? JSON }.map { m in
        let method = m["method"] as? String ?? "?"
        let value = esc(m["value"] as? String ?? "")
        return "\(method)(\(value))"
    }.joined(separator: ", ")
}

// MARK: - Main

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: \(CommandLine.arguments[0]) <run-dir>\n", stderr); exit(1)
}

let runDir = CommandLine.arguments[1]
guard let run = loadJSON(runDir + "/run.json") else {
    fputs("\(runDir)/run.json: not found or invalid\n", stderr); exit(1)
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
        fputs("WARNING: \(resultPath): missing or invalid result.json for test '\(tid)'\n", stderr)
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
            let imgSrc = "\(safeRelpath(tid))/\(safeRelpath(ss))"
            let sdur = (step["duration"] as? Double).map { String(format: "%.1f", $0) + "s" } ?? ""
            stepsHTML += "<div class=\"step-card \(cardCls)\" onclick=\"openLightbox(this.querySelector('img'))\">"
            stepsHTML += "<img src=\"\(esc(imgSrc))\" alt=\"Step \(n)\"><div class=\"step-label\"><span>Step \(n)</span><span>\(sdur)</span></div></div>\n"
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

let outPath = runDir + "/report.html"
do {
    try html.write(toFile: outPath, atomically: true, encoding: .utf8)
    print("Report generated: \(outPath)")
} catch {
    fputs("Failed to write \(outPath): \(error.localizedDescription)\n", stderr)
    exit(1)
}
