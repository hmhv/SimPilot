#!/usr/bin/env swift
// generate_verify_report.swift — Generate report.html for a verification directory.
// Usage: swift generate_verify_report.swift <verify-dir> [--title TITLE] [--status ok|issue (fallback if findings.json missing)]

import Foundation

let variants = ["iphone-light", "iphone-dark", "ipad-light", "ipad-dark"]
let variantLabels = ["iPhone Light", "iPhone Dark", "iPad Light", "iPad Dark"]

func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
     .replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;")
     .replacingOccurrences(of: "\"", with: "&quot;")
     .replacingOccurrences(of: "'", with: "&#39;")
}

func imageDataURI(_ path: String) -> String? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return "data:image/png;base64," + data.base64EncodedString()
}

struct Check {
    let filename: String
    let description: String
    var variants: [String: String] // variant -> filename
}

func discoverChecks(_ verifyDir: String) -> [Check] {
    let fm = FileManager.default
    var files: [String: [String: String]] = [:]
    for variant in variants {
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
        return Check(filename: name, description: desc, variants: files[name]!)
    }
}

// MARK: - Parse arguments

var verifyDir = ""
var title = "Verification"
var statusOverride: String? = nil
var args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < args.count {
    switch args[i] {
    case "--title": i += 1; if i < args.count { title = args[i] }
    case "--status": i += 1; if i < args.count { statusOverride = args[i] }
    default: if verifyDir.isEmpty { verifyDir = args[i] }
    }
    i += 1
}

guard !verifyDir.isEmpty else {
    fputs("Usage: \(CommandLine.arguments[0]) <verify-dir> [--title TITLE] [--status ok|issue (fallback if findings.json missing)]\n", stderr); exit(1)
}

guard FileManager.default.fileExists(atPath: verifyDir) else {
    fputs("\(verifyDir): not found\n", stderr); exit(1)
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
                fputs("WARNING: --status ok but findings.json contains \(findings.count) issue(s); using 'issue'\n", stderr)
            } else if let override = statusOverride, override == "issue" && findings.isEmpty {
                fputs("NOTE: --status issue but findings.json is empty; using 'ok' per findings.json\n", stderr)
            }
        } else {
            // Valid JSON but wrong type (not array of objects)
            fputs("WARNING: findings.json exists but is not an array of objects; treating as 'issue'\n", stderr)
            // status stays "issue" — --status ok cannot override a malformed file
        }
    } else {
        // File exists but is not valid JSON
        fputs("WARNING: findings.json exists but contains invalid JSON; treating as 'issue'\n", stderr)
        // status stays "issue" — --status ok cannot override a malformed file
    }
} else if let override = statusOverride {
    status = override
    if override == "ok" {
        fputs("NOTE: --status ok without findings.json; status is caller-asserted (no independent verification)\n", stderr)
    }
}
// else: no findings.json, no flag → status stays "issue" (fail-safe)

let statusClass = status == "ok" ? "status-ok" : "status-issue"
let statusLabel = status == "ok" ? "All OK" : "Issues Found"

var rows = ""
for check in checks {
    rows += "<tr><td>\(esc(check.description))</td>"
    for variant in variants {
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
tbody td img{width:100%;border-radius:8px;cursor:pointer;transition:transform 0.2s}
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

let outPath = verifyDir + "/report.html"
do {
    try html.write(toFile: outPath, atomically: true, encoding: .utf8)
    print("Report generated: \(outPath)")
} catch {
    fputs("Failed to write \(outPath): \(error.localizedDescription)\n", stderr)
    exit(1)
}
