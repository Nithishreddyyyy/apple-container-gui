//===----------------------------------------------------------------------===//
// Copyright © 2026 Apple Inc. and the container project authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

import Foundation

public struct DiagnosticCheck: Sendable {
    public let title: String
    public let passed: Bool
    public let message: String
}

public struct DiagnosticReport: Sendable {
    public let osCheck: DiagnosticCheck
    public let architectureCheck: DiagnosticCheck
    public let binaryCheck: DiagnosticCheck
    public let serviceProbe: DiagnosticCheck

    public var allPassed: Bool {
        osCheck.passed && architectureCheck.passed && binaryCheck.passed
    }
}

public enum Diagnostics {
    public static func checkOS() -> DiagnosticCheck {
        let osVer = ProcessInfo.processInfo.operatingSystemVersion
        let str = "macOS \(osVer.majorVersion).\(osVer.minorVersion).\(osVer.patchVersion)"
        let passed = osVer.majorVersion >= 14
        return DiagnosticCheck(
            title: "Operating System",
            passed: passed,
            message: "\(str) — \(passed ? "OK" : "needs macOS 14+ (macOS 15+ recommended)")"
        )
    }

    public static func checkArchitecture() -> DiagnosticCheck {
        #if arch(arm64)
        return DiagnosticCheck(
            title: "Hardware Architecture",
            passed: true,
            message: "Apple Silicon (arm64) — OK"
        )
        #else
        return DiagnosticCheck(
            title: "Hardware Architecture",
            passed: false,
            message: "x86_64 architecture detected (Apple Silicon M-series recommended for Apple container)"
        )
        #endif
    }

    public static func checkContainerBinary() -> (check: DiagnosticCheck, path: String?) {
        guard let path = ContainerService.findContainerBinary() else {
            return (
                DiagnosticCheck(
                    title: "Container Binary",
                    passed: false,
                    message: "`container` NOT found on PATH.\n" +
                             "  Install from https://github.com/apple/container/releases, then:\n" +
                             "      container system start"
                ),
                nil
            )
        }

        // Try getting system version
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["system", "version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        var verString = ""
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                let firstLine = str.components(separatedBy: .newlines).first ?? ""
                if !firstLine.isEmpty {
                    verString = " (`\(firstLine.prefix(120))`) "
                }
            }
        } catch {
            verString = " "
        }

        return (
            DiagnosticCheck(
                title: "Container Binary",
                passed: true,
                message: "`container` found at \(path)\(verString)— OK"
            ),
            path
        )
    }

    public static func checkSystemService(binaryPath: String?) -> DiagnosticCheck {
        guard let path = binaryPath else {
            return DiagnosticCheck(
                title: "System Service",
                passed: false,
                message: "System service: unknown (`container` missing)"
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["system", "status", "--format", "json"]
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let stdoutStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stderrStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let state: String
            if stdoutStr.lowercased().contains("\"running\"") || stdoutStr.lowercased().contains("status: running") {
                state = "running"
            } else if !stdoutStr.isEmpty {
                state = String(stdoutStr.prefix(200))
            } else if !stderrStr.isEmpty {
                state = String(stderrStr.prefix(200))
            } else {
                state = "not running"
            }

            return DiagnosticCheck(
                title: "System Service",
                passed: true,
                message: "System service probe: \(state)"
            )
        } catch {
            return DiagnosticCheck(
                title: "System Service",
                passed: false,
                message: "System service probe failed: \(error.localizedDescription)"
            )
        }
    }

    public static func runDiagnostics() -> DiagnosticReport {
        let os = checkOS()
        let arch = checkArchitecture()
        let (bin, path) = checkContainerBinary()
        let svc = checkSystemService(binaryPath: path)
        return DiagnosticReport(
            osCheck: os,
            architectureCheck: arch,
            binaryCheck: bin,
            serviceProbe: svc
        )
    }

    public static func printReport(_ report: DiagnosticReport) {
        print("=== Container GUI-Swift Prerequisites ===")
        print("[\(report.osCheck.passed ? "OK" : "!!")] \(report.osCheck.message)")
        print("[\(report.architectureCheck.passed ? "OK" : "!!")] \(report.architectureCheck.message)")
        print("[\(report.binaryCheck.passed ? "OK" : "!!")] \(report.binaryCheck.message)")
        print("[..] \(report.serviceProbe.message)")
        print()
        print("Tip: Apple Silicon + macOS 15+ recommended. Swift 6.0+ native application.")
    }
}
