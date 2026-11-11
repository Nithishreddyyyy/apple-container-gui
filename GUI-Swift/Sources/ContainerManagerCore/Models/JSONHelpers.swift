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

public enum JSONHelpers {
    /// Walk nested dictionaries along *path*; return nil if anything is missing.
    public static func nested(_ dict: [String: Any]?, _ path: String...) -> Any? {
        guard var current: Any = dict else { return nil }
        for key in path {
            guard let d = current as? [String: Any], let next = d[key] else {
                return nil
            }
            current = next
        }
        return current
    }

    /// Convert any scalar value to String, skipping arrays and dictionaries.
    public static func str(_ value: Any?, default: String = "") -> String {
        guard let v = value else { return `default` }
        if v is [Any] || v is [String: Any] {
            return `default`
        }
        let s = String(describing: v).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? `default` : s
    }

    /// Return the first present, non-empty scalar value for any of *keys* (with case-insensitive fallback).
    public static func first(_ dict: [String: Any], _ keys: String..., default: String = "") -> String {
        for k in keys {
            if let v = dict[k] {
                if v is [Any] || v is [String: Any] {
                    continue
                }
                let s = String(describing: v).trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty {
                    return s
                }
            }
        }

        // Case-insensitive fallback
        var lowered = [String: Any]()
        for (k, v) in dict {
            lowered[k.lowercased()] = v
        }

        for k in keys {
            if let v = lowered[k.lowercased()] {
                if v is [Any] || v is [String: Any] {
                    continue
                }
                let s = String(describing: v).trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty {
                    return s
                }
            }
        }
        return `default`
    }

    /// Split `registry/name:tag` into (name, tag). Digest refs keep tag="".
    public static func splitRef(_ ref: String) -> (name: String, tag: String) {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("@sha256") || trimmed.hasPrefix("sha256:") {
            return (trimmed, "")
        }

        if trimmed.contains(":") && trimmed.contains("/") {
            // Find last colon
            if let lastColonIndex = trimmed.lastIndex(of: ":") {
                let name = String(trimmed[..<lastColonIndex])
                let tag = String(trimmed[trimmed.index(after: lastColonIndex)...])
                if tag.contains("/") || tag.isEmpty {
                    return (trimmed, "")
                }
                return (name, tag)
            }
            return (trimmed, "")
        }

        if trimmed.contains(":") {
            if let lastColonIndex = trimmed.lastIndex(of: ":") {
                let name = String(trimmed[..<lastColonIndex])
                let tag = String(trimmed[trimmed.index(after: lastColonIndex)...])
                if !tag.isEmpty && !tag.contains("/") {
                    return (name, tag)
                }
            }
            return (trimmed, "")
        }

        return (trimmed, "")
    }

    /// Format byte size into human readable string (B, KB, MB, GB, TB).
    public static func fmtSize(_ value: Any?) -> String {
        guard let v = value else { return "" }
        let num: Int64
        if let i = v as? Int64 {
            num = i
        } else if let i = v as? Int {
            num = Int64(i)
        } else if let d = v as? Double {
            num = Int64(d)
        } else if let s = v as? String, let parsed = Int64(s) {
            num = parsed
        } else {
            return str(v)
        }

        if num < 0 {
            return str(v)
        }

        let units = ["B", "KB", "MB", "GB", "TB"]
        var f = Double(num)
        for (idx, u) in units.enumerated() {
            if f < 1024.0 || idx == units.count - 1 {
                if u == "B" {
                    return "\(num) B"
                } else {
                    return String(format: "%.1f %@", f, u)
                }
            }
            f /= 1024.0
        }
        return "\(num) B"
    }

    /// Extract IP string from status networks array.
    public static func ipFromNetworks(_ networks: Any?) -> String {
        guard let list = networks as? [Any] else { return "" }
        var ips: [String] = []
        for item in list {
            if let s = item as? String, !s.isEmpty {
                ips.append(s)
            } else if let d = item as? [String: Any] {
                for k in ["address", "ip", "ipAddress", "IPAddress"] {
                    if let val = d[k] {
                        let s = String(describing: val).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !s.isEmpty {
                            ips.append(s)
                            break
                        }
                    }
                }
            }
        }
        return ips.joined(separator: ", ")
    }
}
