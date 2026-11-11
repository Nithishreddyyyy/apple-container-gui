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
import ContainerManagerCore

let argv = CommandLine.arguments

if argv.contains("--help") || argv.contains("-h") {
    print("""
    Container Manager (GUI-Swift) Launcher & Diagnostics

    Usage:
        swift run ContainerManagerLauncher          # Run diagnostics and launch recommendations
        swift run ContainerManagerLauncher --check  # Diagnostics only, exit 0/1
        swift run ContainerManagerApp               # Launch the native SwiftUI GUI directly
        swift run ContainerManagerLauncher --help   # Show this help

    Requirements:
        - macOS 14+ (macOS 15+ recommended)
        - Apple Silicon (arm64)
        - Apple container CLI installed and on PATH
    """)
    exit(0)
}

let report = Diagnostics.runDiagnostics()
Diagnostics.printReport(report)

if argv.contains("--check") {
    if report.allPassed {
        print()
        print("All checks passed (check-only mode).")
        exit(0)
    } else {
        print()
        print("Missing prerequisites. Fix the items marked [!!] above and retry.")
        exit(1)
    }
}

if !report.allPassed {
    print()
    print("Missing prerequisites — GUI not launched. Fix the items marked [!!] above and retry.")
    exit(1)
}

print()
print("Launching Container Manager (SwiftUI)...")
print("To start the graphical window, execute: swift run ContainerManagerApp")
exit(0)
