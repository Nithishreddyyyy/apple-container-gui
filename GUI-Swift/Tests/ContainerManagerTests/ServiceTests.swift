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
@testable import ContainerManagerCore

@Suite("Service & Adapter Tests")
struct ServiceTests {
    @Test("JSON Array parsing handles arrays, empty input, and malformed strings")
    func parseJSONArray() throws {
        let arr = try ContainerService.parseJSONArray("[{\"id\": \"a\"}]")
        #expect(arr.count == 1)
        #expect(arr[0]["id"] as? String == "a")

        let empty = try ContainerService.parseJSONArray("")
        #expect(empty.isEmpty)

        #expect(throws: ContainerCLIError.self) {
            _ = try ContainerService.parseJSONArray("not json{")
        }
    }

    @Test("JSON Object parsing handles objects and empty input")
    func parseJSONObject() throws {
        let obj = try ContainerService.parseJSONObject("{\"status\": \"running\"}")
        #expect(obj["status"] as? String == "running")

        let empty = try ContainerService.parseJSONObject("")
        #expect(empty.isEmpty)
    }

    @Test("Daemon down hint detection triggers on known error markers")
    func daemonHint() {
        #expect(
            ContainerCLIError.daemonDownHint(
                "Error: failed to list containers. Ensure container system service has been started"
            )
        )
        #expect(
            ContainerCLIError.daemonDownHint("XPC connection error: Connection invalid")
        )
        #expect(
            !ContainerCLIError.daemonDownHint("some other error occurred: file not found")
        )
    }
}
