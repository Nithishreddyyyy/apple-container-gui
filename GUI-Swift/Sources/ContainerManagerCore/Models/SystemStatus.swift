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

/// Result of `container system status --format json`.
public struct SystemStatus: Sendable, Equatable {
    public let status: String
    public let apiServerVersion: String
    public let installRoot: String
    public let appRoot: String

    public init(
        status: String = "unknown",
        apiServerVersion: String = "",
        installRoot: String = "",
        appRoot: String = ""
    ) {
        self.status = status
        self.apiServerVersion = apiServerVersion
        self.installRoot = installRoot
        self.appRoot = appRoot
    }

    public var isRunning: Bool {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "running"
    }

    public static func from(dict: [String: Any]) -> SystemStatus {
        let st = JSONHelpers.first(dict, "status", "Status", default: "unknown")
        let ver = JSONHelpers.str(dict["apiServerVersion"])
        let inst = JSONHelpers.str(dict["installRoot"])
        let app = JSONHelpers.str(dict["appRoot"])
        return SystemStatus(
            status: st,
            apiServerVersion: ver,
            installRoot: inst,
            appRoot: app
        )
    }
}
