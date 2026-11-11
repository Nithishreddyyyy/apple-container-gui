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
import Testing
@testable import ContainerManagerCore
@testable import ContainerManagerApp

@Suite("Action refresh regression tests")
@MainActor
struct AppViewModelTests {
    @Test("Successful mutations refresh their data without reentering the busy guard",
          arguments: ["run", "pull", "start", "stop", "restart", "remove", "removeImage", "systemStart", "systemStop"])
    func mutationRefresh(action: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = directory.appendingPathComponent("container-stub")
        // No daemon or registry access: exercise the real Process adapter with deterministic output.
        let script = """
        #!/bin/sh
        case "$1 $2" in
          "list --all") echo '[{"id":"test-container","status":"running"}]' ;;
          "image list") echo '[{"reference":"alpine:latest"}]' ;;
          "system status") echo '{"status":"running"}' ;;
          *) echo 'ok' ;;
        esac
        """
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let model = AppViewModel(service: try ContainerService(binary: binary.path))
        switch action {
        case "run": model.runContainer(image: "alpine:latest", name: "example")
        case "pull": model.pullImage(ref: "alpine:latest")
        case "start": model.startContainer(id: "test-container")
        case "stop": model.stopContainer(id: "test-container")
        case "restart": model.restartContainer(id: "test-container")
        case "remove": model.removeContainer(id: "test-container")
        case "removeImage": model.removeImage(ref: "alpine:latest")
        case "systemStart": model.startSystem()
        default: model.stopSystem()
        }
        #expect(model.isBusy)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.isBusy && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!model.isBusy)
        #expect(model.errorMessage == nil)
        if action == "pull" || action == "removeImage" {
            #expect(model.images.count == 1)
            #expect(model.commandOutput.contains("$ container image list"))
        } else if action.hasPrefix("system") {
            #expect(model.systemStatus.isRunning)
            #expect(model.commandOutput.contains("$ container system status"))
        } else {
            #expect(model.containers.count == 1)
            #expect(model.commandOutput.contains("$ container list --all"))
        }
    }
}
