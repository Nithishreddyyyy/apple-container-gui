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

@Suite("Validation Tests")
struct ValidationTests {
    @Test("Valid identifiers are accepted")
    func validIds() throws {
        let valid = [
            "web",
            "my-container_1",
            "alpine:latest",
            "registry.io/lib/img@sha256:abc",
            "a/b/c"
        ]
        for v in valid {
            let res = try Validation.validateIdentifier(v)
            #expect(res == v)
        }
    }

    @Test("Shell metacharacters are rejected")
    func rejectsShellMetachars() {
        let invalid = [
            "a;rm -rf /",
            "$(evil)",
            "`evil`",
            "a|b",
            "a&b",
            "a b",
            "a'b",
            "a\"b",
            "a\\b",
            "a>b",
            "$HOME",
            ""
        ]
        for v in invalid {
            #expect(throws: ContainerCLIError.self) {
                try Validation.validateIdentifier(v)
            }
        }
    }

    @Test("Identifiers exceeding max length (256 chars) are rejected")
    func rejectsTooLong() {
        let longId = String(repeating: "x", count: 300)
        #expect(throws: ContainerCLIError.self) {
            try Validation.validateIdentifier(longId)
        }
    }

    @Test("Image references validation")
    func imageRefValidation() throws {
        let valid = try Validation.validateImageRef("alpine:latest")
        #expect(valid == "alpine:latest")

        #expect(throws: ContainerCLIError.self) {
            try Validation.validateImageRef("alpine; echo hi")
        }
    }
}
