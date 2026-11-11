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

public enum ContainerCLIError: LocalizedError, Equatable {
    case binaryNotFound(String)
    case executionFailed(String)
    case timedOut(command: String, timeout: TimeInterval)
    case invalidIdentifier(String)
    case invalidJSON(String)
    case custom(String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound(let msg):
            return msg
        case .executionFailed(let msg):
            return msg
        case .timedOut(let command, let timeout):
            return "Timed out running `\(command)` after \(Int(timeout))s"
        case .invalidIdentifier(let msg):
            return msg
        case .invalidJSON(let msg):
            return "Could not parse CLI JSON output: \(msg)"
        case .custom(let msg):
            return msg
        }
    }

    /// Check if stderr/stdout indicates that the daemon or system service is down.
    public static func daemonDownHint(_ output: String) -> Bool {
        let markers = [
            "Ensure container system service has been started",
            "Connection invalid",
            "failed to list containers",
            "apiserver",
            "not running",
            "unregistered"
        ]
        let lower = output.lowercased()
        return markers.contains { lower.contains($0.lowercased()) }
    }

    /// Format an error message from CLIResult, appending the daemon-down hint if relevant.
    public static func formatErrorMessage(stdout: String, stderr: String, returncode: Int32) -> String {
        let cleanErr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanOut = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        var msg = !cleanErr.isEmpty ? cleanErr : (!cleanOut.isEmpty ? cleanOut : "Process exited with code \(returncode)")

        if daemonDownHint(stderr + stdout) {
            msg += "\n\nHint: the container system service looks stopped. Run `container system start` (System tab) and retry."
        }
        return msg
    }
}
