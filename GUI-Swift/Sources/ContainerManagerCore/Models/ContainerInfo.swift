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

/// A single container row for the dashboard.
public struct ContainerInfo: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let image: String
    public let state: String
    public let ip: String
    public let os: String
    public let arch: String
    public let started: String

    public init(
        id: String = "",
        name: String = "",
        image: String = "",
        state: String = "",
        ip: String = "",
        os: String = "",
        arch: String = "",
        started: String = ""
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
        self.ip = ip
        self.os = os
        self.arch = arch
        self.started = started
    }

    public var displayName: String {
        name.isEmpty ? id : name
    }

    public var isRunning: Bool {
        let s = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["running", "up", "started"].contains(s)
    }

    public var osArch: String {
        let parts = [os, arch].filter { !$0.isEmpty }
        return parts.joined(separator: "/")
    }

    /// Construct from tolerant CLI dictionary (handles real CLI 1.x nested shape as well as flat fallbacks).
    public static func from(dict: [String: Any]) -> ContainerInfo {
        let cfg = dict["configuration"] as? [String: Any] ?? [:]
        let stDict = dict["status"] as? [String: Any] ?? [:]
        let statusStr = dict["status"] as? String

        let state: String
        if let s = statusStr, !s.isEmpty {
            state = s
        } else {
            let nestedState = JSONHelpers.str(JSONHelpers.nested(stDict, "state"))
            state = nestedState.isEmpty ? JSONHelpers.first(dict, "state", "State") : nestedState
        }

        let plat = cfg["platform"] as? [String: Any] ?? [:]
        let imgObj = cfg["image"]
        let image: String
        if let imgDict = imgObj as? [String: Any] {
            image = JSONHelpers.str(JSONHelpers.nested(imgDict, "reference"))
        } else {
            image = JSONHelpers.str(imgObj)
        }

        let cidVal = JSONHelpers.first(dict, "id", "ID")
        let cid = cidVal.isEmpty ? JSONHelpers.str(JSONHelpers.nested(cfg, "id")) : cidVal

        let nameFromFirst = JSONHelpers.first(dict, "name", "Name")
        let nameFromCfg = JSONHelpers.str(JSONHelpers.nested(cfg, "name"))
        let hostFromCfg = JSONHelpers.str(JSONHelpers.nested(cfg, "hostname"))
        let name: String
        if !nameFromFirst.isEmpty {
            name = nameFromFirst
        } else if !nameFromCfg.isEmpty {
            name = nameFromCfg
        } else if !hostFromCfg.isEmpty {
            name = hostFromCfg
        } else {
            name = cid
        }

        let ipFromSt = JSONHelpers.ipFromNetworks(JSONHelpers.nested(stDict, "networks"))
        let ipFromD = JSONHelpers.ipFromNetworks(JSONHelpers.nested(dict, "networks"))
        let ipFromFirst = JSONHelpers.first(dict, "ip", "IP", "address", "Address", "ipAddress")
        let ip: String
        if !ipFromSt.isEmpty {
            ip = ipFromSt
        } else if !ipFromD.isEmpty {
            ip = ipFromD
        } else {
            ip = ipFromFirst
        }

        let osVal = JSONHelpers.str(JSONHelpers.nested(plat, "os"))
        let finalOs = osVal.isEmpty ? JSONHelpers.first(dict, "os", "OS") : osVal

        let archVal = JSONHelpers.str(JSONHelpers.nested(plat, "architecture"))
        let finalArch = archVal.isEmpty ? JSONHelpers.first(dict, "arch", "Arch", "architecture") : archVal

        let startedVal = JSONHelpers.str(JSONHelpers.nested(cfg, "creationDate"))
        let finalStarted = startedVal.isEmpty ? JSONHelpers.first(dict, "started", "Started", "created", "Created") : startedVal

        let finalImage = image.isEmpty ? JSONHelpers.first(dict, "image", "Image") : image

        return ContainerInfo(
            id: cid,
            name: name,
            image: finalImage,
            state: state,
            ip: ip,
            os: finalOs,
            arch: finalArch,
            started: finalStarted
        )
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(state)
    }
}
