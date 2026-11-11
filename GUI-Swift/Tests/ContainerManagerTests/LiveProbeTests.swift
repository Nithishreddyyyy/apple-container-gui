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

import Testing
import Foundation
@testable import ContainerManagerCore

@Suite("Live CLI Probe Tests")
struct LiveProbeTests {
    @Test("container binary is discovered and --help works")
    func binaryPresentAndHelpWorks() throws {
        guard let binary = ContainerService.findContainerBinary() else {
            Issue.record("`container` binary not found on PATH or standard directories")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["--help"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        let output = (String(data: data, encoding: .utf8) ?? "").lowercased()
        #expect(output.contains("container"))
    }

    @Test("system status probe succeeds or returns graceful error without crashing")
    func systemStatusProbe() async throws {
        guard let binary = ContainerService.findContainerBinary() else {
            return
        }

        do {
            let svc = try ContainerService(binary: binary)
            let st = try await svc.systemStatus()
            let lower = st.status.lowercased()
            let expected = ["running", "not running", "unregistered", "unknown"]
            #expect(expected.contains(where: { lower.contains($0) }))
        } catch {
            let msg = error.localizedDescription.lowercased()
            #expect(msg.contains("system") || msg.contains("container"))
        }
    }
}
