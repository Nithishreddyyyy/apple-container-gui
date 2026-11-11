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

public enum Validation {
    private static let maxIdLength = 256
    // Allowlist: letters, digits, and `_ . - / : @`
    private static let identifierRegex = try! NSRegularExpression(pattern: "^[A-Za-z0-9_./:@\\-]+$")

    /// Validate a user-controlled CLI argument against allowlist. Throws ContainerCLIError.
    @discardableResult
    public static func validateIdentifier(_ value: String, kind: String = "identifier") throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw ContainerCLIError.invalidIdentifier("\(kind) must not be empty")
        }
        if trimmed.count > maxIdLength {
            throw ContainerCLIError.invalidIdentifier("\(kind) is too long (max \(maxIdLength) chars)")
        }

        let range = NSRange(location: 0, length: trimmed.utf16.count)
        if identifierRegex.firstMatch(in: trimmed, options: [], range: range) == nil {
            throw ContainerCLIError.invalidIdentifier(
                "Invalid \(kind) '\(trimmed)': only letters, digits and `_ . - / : @` are allowed"
            )
        }
        return trimmed
    }

    /// Validate an image reference (e.g. `alpine:latest`, `registry.io/org/repo:tag`).
    @discardableResult
    public static func validateImageRef(_ value: String) throws -> String {
        try validateIdentifier(value, kind: "image reference")
    }
}
