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

@Suite("Real CLI Schema Compatibility Tests")
@MainActor
struct RealSchemaTests {
    static let realContainer: [String: Any] = [
        "configuration": [
            "creationDate": "2026-10-05T05:57:33Z",
            "id": "6b60e808-f78f-4fc1-8703-87df0b4f9381",
            "image": ["reference": "docker.io/library/ubuntu:latest"],
            "platform": ["architecture": "arm64", "os": "linux"]
        ],
        "id": "6b60e808-f78f-4fc1-8703-87df0b4f9381",
        "status": ["networks": [] as [Any], "state": "stopped"]
    ]

    static let realContainerRunning: [String: Any] = [
        "configuration": [
            "creationDate": "2026-10-05T05:57:33Z",
            "id": "6b60e808-f78f-4fc1-8703-87df0b4f9381",
            "image": ["reference": "docker.io/library/ubuntu:latest"],
            "platform": ["architecture": "arm64", "os": "linux"]
        ],
        "id": "6b60e808-f78f-4fc1-8703-87df0b4f9381",
        "status": [
            "networks": [["address": "192.168.64.2"]],
            "state": "running"
        ]
    ]

    static let realImage: [String: Any] = [
        "configuration": ["name": "docker.io/library/ubuntu:latest"],
        "id": "f144425ff09be612d6d9ad965196e9cdc23dae1f42110a8a11a3e9a8198759f7",
        "variants": [[
            "digest": "sha256:3ad1c71aa6b7e477f7aa91445a5442fbb163",
            "platform": ["architecture": "arm64", "os": "linux"],
            "size": 40871017
        ]]
    ]

    @Test("Real CLI container schema decodes accurately")
    func realContainerParses() {
        let c = ContainerInfo.from(dict: Self.realContainer)
        #expect(c.id == "6b60e808-f78f-4fc1-8703-87df0b4f9381")
        #expect(c.image == "docker.io/library/ubuntu:latest")
        #expect(c.state == "stopped")
        #expect(c.os == "linux")
        #expect(c.arch == "arm64")
        #expect(!c.isRunning)
    }

    @Test("Real running container with networks decodes IP accurately")
    func realRunningContainerParses() {
        let c = ContainerInfo.from(dict: Self.realContainerRunning)
        #expect(c.isRunning)
        #expect(c.state == "running")
        #expect(c.ip.contains("192.168.64.2"))
    }

    @Test("Real image schema decodes size, digest, and platform accurately")
    func realImageParses() {
        let im = ImageInfo.from(dict: Self.realImage)
        #expect(im.name == "docker.io/library/ubuntu")
        #expect(im.tag == "latest")
        #expect(im.os == "linux")
        #expect(im.arch == "arm64")
        #expect(!im.size.isEmpty)
        #expect(im.size != "0 B")
        #expect(im.digest.hasPrefix("sha256:"))
    }
}
