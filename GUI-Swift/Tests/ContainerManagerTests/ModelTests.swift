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

@Suite("Data Model Tests")
struct ModelTests {
    @Test("ContainerInfo parses from dictionary")
    func containerFromDict() {
        let dict: [String: Any] = [
            "id": "abc123",
            "name": "web",
            "image": "nginx:latest",
            "state": "running",
            "ip": "192.168.1.2",
            "os": "linux",
            "arch": "arm64"
        ]
        let c = ContainerInfo.from(dict: dict)
        #expect(c.displayName == "web")
        #expect(c.isRunning)
        #expect(c.osArch == "linux/arm64")

        let stoppedDict: [String: Any] = [
            "ID": "x",
            "Status": "Stopped"
        ]
        let c2 = ContainerInfo.from(dict: stoppedDict)
        #expect(!c2.isRunning)
        #expect(c2.id == "x")
    }

    @Test("ImageInfo parses from dictionary")
    func imageFromDict() {
        let dict: [String: Any] = [
            "name": "alpine",
            "tag": "latest",
            "os": "linux",
            "arch": "arm64"
        ]
        let im = ImageInfo.from(dict: dict)
        #expect(im.reference == "alpine:latest")
        #expect(im.osArch == "linux/arm64")
    }

    @Test("SystemStatus parses running state")
    func systemStatus() {
        let running = SystemStatus.from(dict: ["status": "running"])
        #expect(running.isRunning)

        let unreg = SystemStatus.from(dict: ["status": "unregistered"])
        #expect(!unreg.isRunning)
    }

    @Test("Human-readable byte formatting")
    func sizeFormatting() {
        #expect(JSONHelpers.fmtSize(500) == "500 B")
        #expect(JSONHelpers.fmtSize(2048) == "2.0 KB")
        #expect(JSONHelpers.fmtSize(10485760) == "10.0 MB")
        #expect(JSONHelpers.fmtSize("1073741824") == "1.0 GB")
    }

    @Test("Image reference splitting into repository and tag")
    func splitRef() {
        let (n1, t1) = JSONHelpers.splitRef("ubuntu:latest")
        #expect(n1 == "ubuntu")
        #expect(t1 == "latest")

        let (n2, t2) = JSONHelpers.splitRef("registry.example.com:5000/myimage:v1.2")
        #expect(n2 == "registry.example.com:5000/myimage")
        #expect(t2 == "v1.2")

        let (n3, t3) = JSONHelpers.splitRef("alpine")
        #expect(n3 == "alpine")
        #expect(t3 == "")
    }
}
