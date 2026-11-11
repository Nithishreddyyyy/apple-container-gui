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

/// A single image row for the images view.
public struct ImageInfo: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let tag: String
    public let digest: String
    public let os: String
    public let arch: String
    public let size: String
    public let created: String

    public init(
        id: String = UUID().uuidString,
        name: String = "",
        tag: String = "",
        digest: String = "",
        os: String = "",
        arch: String = "",
        size: String = "",
        created: String = ""
    ) {
        self.id = id
        self.name = name
        self.tag = tag
        self.digest = digest
        self.os = os
        self.arch = arch
        self.size = size
        self.created = created
    }

    public var reference: String {
        if !name.isEmpty && !tag.isEmpty {
            return "\(name):\(tag)"
        }
        return !name.isEmpty ? name : digest
    }

    public var osArch: String {
        let parts = [os, arch].filter { !$0.isEmpty }
        return parts.joined(separator: "/")
    }

    /// Construct from tolerant CLI dictionary (handles real CLI 1.x nested shape as well as flat fallbacks).
    public static func from(dict: [String: Any]) -> ImageInfo {
        let cfg = dict["configuration"] as? [String: Any] ?? [:]
        let variants = dict["variants"] as? [[String: Any]] ?? []
        let firstVariant = variants.first ?? [:]
        let vplat = firstVariant["platform"] as? [String: Any] ?? [:]

        let nameFromCfg = JSONHelpers.str(JSONHelpers.nested(cfg, "name"))
        let fullRefVal = !nameFromCfg.isEmpty ? nameFromCfg : JSONHelpers.first(dict, "name", "Name", "repository", "Repository")

        var (name, tag) = JSONHelpers.splitRef(fullRefVal)
        if tag.isEmpty {
            let tagFromFirst = JSONHelpers.first(dict, "tag", "Tag")
            if !tagFromFirst.isEmpty {
                tag = tagFromFirst
                if name.isEmpty {
                    name = fullRefVal
                }
            }
        }

        let digestVal = JSONHelpers.str(JSONHelpers.nested(firstVariant, "digest"))
        let digestFromFirst = JSONHelpers.first(dict, "digest", "Digest", "manifestDigest", "ManifestDigest")
        let rawId = JSONHelpers.str(dict["id"])
        let digest: String
        if !digestVal.isEmpty {
            digest = digestVal
        } else if !digestFromFirst.isEmpty {
            digest = digestFromFirst
        } else {
            digest = rawId
        }

        let sizeRaw: Any?
        if firstVariant["size"] != nil {
            sizeRaw = firstVariant["size"]
        } else if dict["size"] != nil {
            sizeRaw = dict["size"]
        } else {
            sizeRaw = dict["fullSize"]
        }

        let osVal = JSONHelpers.str(JSONHelpers.nested(vplat, "os"))
        let finalOs = !osVal.isEmpty ? osVal : JSONHelpers.first(dict, "os", "OS")

        let archVal = JSONHelpers.str(JSONHelpers.nested(vplat, "architecture"))
        let finalArch = !archVal.isEmpty ? archVal : JSONHelpers.first(dict, "arch", "Arch", "architecture")

        let createdFromCfg = JSONHelpers.str(JSONHelpers.nested(cfg, "creationDate"))
        let createdFromVariant = JSONHelpers.str(JSONHelpers.nested(firstVariant, "created"))
        let createdFromFirst = JSONHelpers.first(dict, "created", "Created")
        let finalCreated: String
        if !createdFromCfg.isEmpty {
            finalCreated = createdFromCfg
        } else if !createdFromVariant.isEmpty {
            finalCreated = createdFromVariant
        } else {
            finalCreated = createdFromFirst
        }

        let finalName = !name.isEmpty ? name : fullRefVal
        let syntheticId = !digest.isEmpty ? digest : "\(finalName):\(tag)"

        return ImageInfo(
            id: syntheticId.isEmpty ? UUID().uuidString : syntheticId,
            name: finalName,
            tag: tag,
            digest: digest,
            os: finalOs,
            arch: finalArch,
            size: JSONHelpers.fmtSize(sizeRaw),
            created: finalCreated
        )
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(reference)
        hasher.combine(digest)
    }
}
