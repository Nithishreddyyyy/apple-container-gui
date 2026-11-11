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

public final class ContainerService: Sendable {
    public static let defaultTimeout: TimeInterval = 30
    public static let maxOutputBytes = 512 * 1024

    public let binary: String
    public let timeout: TimeInterval

    public init(binary: String? = nil, timeout: TimeInterval = defaultTimeout) throws {
        guard let resolved = ContainerService.findContainerBinary(explicit: binary) else {
            throw ContainerCLIError.binaryNotFound(
                "The `container` command was not found on PATH. " +
                "Install it from https://github.com/apple/container/releases " +
                "and run `container system start`."
            )
        }
        self.binary = resolved
        self.timeout = timeout
    }

    /// Resolve the `container` binary path, or nil if not installed.
    public static func findContainerBinary(explicit: String? = nil) -> String? {
        var candidates: [String] = []
        if let exp = explicit, !exp.isEmpty {
            candidates.append(exp)
        }
        if let env = ProcessInfo.processInfo.environment["CONTAINER_CLI"], !env.isEmpty {
            candidates.append(env)
        }
        candidates.append("container")
        candidates.append("/opt/homebrew/opt/container/bin/container")
        candidates.append("/opt/homebrew/bin/container")
        candidates.append("/usr/local/bin/container")

        let fm = FileManager.default

        // Get PATH directories
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) }

        for c in candidates {
            if c.contains("/") {
                if fm.isExecutableFile(atPath: c) {
                    return c
                }
            } else {
                for dir in pathDirs {
                    let full = (dir as NSString).appendingPathComponent(c)
                    if fm.isExecutableFile(atPath: full) {
                        return full
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Low-Level Process Execution

    /// Execute a command safely via Process (never shell string).
    public func runRaw(args: [String], timeout: TimeInterval? = nil) async throws -> CLIResult {
        let effectiveTimeout = timeout ?? self.timeout
        let argv = [self.binary] + args

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.binary)
                process.arguments = args

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                final class PipeBox: @unchecked Sendable {
                    var data = Data()
                }
                let stdoutBox = PipeBox()
                let stderrBox = PipeBox()
                let group = DispatchGroup()

                group.enter()
                DispatchQueue.global().async {
                    stdoutBox.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                group.enter()
                DispatchQueue.global().async {
                    stderrBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ContainerCLIError.executionFailed("Failed to launch `\(argv.joined(separator: " "))`: \(error.localizedDescription)"))
                    return
                }

                // Handle timeout
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                var timedOut = false
                timer.schedule(deadline: .now() + effectiveTimeout)
                timer.setEventHandler {
                    timedOut = true
                    process.terminate()
                }
                timer.resume()

                process.waitUntilExit()
                timer.cancel()
                group.wait()

                if timedOut {
                    continuation.resume(throwing: ContainerCLIError.timedOut(command: argv.joined(separator: " "), timeout: effectiveTimeout))
                    return
                }

                let cappedStdout = stdoutBox.data.prefix(Self.maxOutputBytes)
                let cappedStderr = stderrBox.data.prefix(Self.maxOutputBytes)

                let stdoutStr = String(data: cappedStdout, encoding: .utf8)
                    ?? String(decoding: cappedStdout, as: UTF8.self)
                let stderrStr = String(data: cappedStderr, encoding: .utf8)
                    ?? String(decoding: cappedStderr, as: UTF8.self)

                let res = CLIResult(
                    returncode: process.terminationStatus,
                    stdout: stdoutStr,
                    stderr: stderrStr,
                    argv: argv
                )
                continuation.resume(returning: res)
            }
        }
    }

    @discardableResult
    public func ensureOk(_ res: CLIResult) throws -> CLIResult {
        if res.ok {
            return res
        }
        let msg = ContainerCLIError.formatErrorMessage(
            stdout: res.stdout,
            stderr: res.stderr,
            returncode: res.returncode
        )
        throw ContainerCLIError.executionFailed(msg)
    }

    // MARK: - JSON Parsing Helpers

    public static func parseJSONArray(_ stdout: String) throws -> [[String: Any]] {
        let text = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return []
        }
        guard let data = text.data(using: .utf8) else {
            throw ContainerCLIError.invalidJSON("Could not encode CLI output as UTF-8")
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ContainerCLIError.invalidJSON(error.localizedDescription)
        }

        if let array = jsonObject as? [[String: Any]] {
            return array
        }
        if let dict = jsonObject as? [String: Any] {
            for key in ["items", "containers", "images"] {
                if let arr = dict[key] as? [[String: Any]] {
                    return arr
                }
            }
            return [dict]
        }
        throw ContainerCLIError.invalidJSON("Unexpected JSON shape from CLI (not array or dictionary)")
    }

    public static func parseJSONObject(_ stdout: String) throws -> [String: Any] {
        let text = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return [:]
        }
        guard let data = text.data(using: .utf8) else {
            throw ContainerCLIError.invalidJSON("Could not encode CLI output as UTF-8")
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ContainerCLIError.invalidJSON(error.localizedDescription)
        }

        if let dict = jsonObject as? [String: Any] {
            return dict
        }
        if let array = jsonObject as? [[String: Any]], let first = array.first {
            return first
        }
        throw ContainerCLIError.invalidJSON("Unexpected JSON shape from CLI (not a JSON object)")
    }

    // MARK: - Container Operations

    public func listContainers() async throws -> [ContainerInfo] {
        let res = try ensureOk(await runRaw(args: ["list", "--all", "--format", "json"]))
        let arr = try Self.parseJSONArray(res.stdout)
        return arr.map { ContainerInfo.from(dict: $0) }
    }

    public func startContainer(id: String) async throws -> CLIResult {
        let cid = try Validation.validateIdentifier(id, kind: "container id")
        let res = try await runRaw(args: ["start", cid])
        return try ensureOk(res)
    }

    public func stopContainer(id: String, timeoutSecs: Int = 5) async throws -> CLIResult {
        let cid = try Validation.validateIdentifier(id, kind: "container id")
        let effectiveTimeout = max(self.timeout, Double(timeoutSecs) + 15)
        let res = try await runRaw(
            args: ["stop", "--time", "\(timeoutSecs)", cid],
            timeout: effectiveTimeout
        )
        return try ensureOk(res)
    }

    public func restartContainer(id: String) async throws -> CLIResult {
        // No dedicated `restart` subcommand in Apple's container CLI; stop then start
        let cid = try Validation.validateIdentifier(id, kind: "container id")
        _ = try ensureOk(await runRaw(args: ["stop", cid]))
        return try ensureOk(await runRaw(args: ["start", cid]))
    }

    public func removeContainer(id: String, force: Bool = false) async throws -> CLIResult {
        let cid = try Validation.validateIdentifier(id, kind: "container id")
        var args = ["rm"]
        if force {
            args.append("--force")
        }
        args.append(cid)

        let res = try await runRaw(args: args)
        if !res.ok && res.stderr.lowercased().contains("unknown command") {
            var fallbackArgs = ["delete"]
            if force {
                fallbackArgs.append("--force")
            }
            fallbackArgs.append(cid)
            return try ensureOk(await runRaw(args: fallbackArgs))
        }
        return try ensureOk(res)
    }

    public func containerLogs(id: String, tail: Int = 200) async throws -> CLIResult {
        let cid = try Validation.validateIdentifier(id, kind: "container id")
        let res = try await runRaw(args: ["logs", "--number", "\(tail)", cid])
        return try ensureOk(res)
    }

    public func inspectContainer(id: String) async throws -> String {
        let cid = try Validation.validateIdentifier(id, kind: "container id")
        let res = try ensureOk(await runRaw(args: ["inspect", cid]))
        return res.stdout
    }

    public func runContainer(image: String, name: String = "", extraArgs: [String]? = nil) async throws -> CLIResult {
        let ref = try Validation.validateImageRef(image)
        var args = ["run", "--detach"]
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            let validName = try Validation.validateIdentifier(trimmedName, kind: "container name")
            args.append(contentsOf: ["--name", validName])
        }
        if let extras = extraArgs, !extras.isEmpty {
            throw ContainerCLIError.custom("Extra run flags are not supported by the GUI")
        }
        args.append(ref)
        let res = try await runRaw(args: args, timeout: 120)
        return try ensureOk(res)
    }

    // MARK: - Image Operations

    public func listImages() async throws -> [ImageInfo] {
        let res = try ensureOk(await runRaw(args: ["image", "list", "--format", "json"]))
        let arr = try Self.parseJSONArray(res.stdout)
        return arr.map { ImageInfo.from(dict: $0) }
    }

    public func pullImage(ref: String) async throws -> CLIResult {
        let r = try Validation.validateImageRef(ref)
        let res = try await runRaw(args: ["image", "pull", "--progress", "plain", r], timeout: 600)
        return try ensureOk(res)
    }

    public func removeImage(ref: String, force: Bool = false) async throws -> CLIResult {
        let r = try Validation.validateImageRef(ref)
        var args = ["image", "rm"]
        if force {
            args.append("--force")
        }
        args.append(r)
        let res = try await runRaw(args: args, timeout: 120)
        return try ensureOk(res)
    }

    // MARK: - System Operations

    public func systemStatus() async throws -> SystemStatus {
        let res = try await runRaw(args: ["system", "status", "--format", "json"])
        do {
            let dict = try Self.parseJSONObject(res.stdout)
            return SystemStatus.from(dict: dict)
        } catch {
            if res.ok {
                throw error
            }
            let cleanErr = res.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseMsg = !cleanErr.isEmpty ? cleanErr : "container system is not running"
            throw ContainerCLIError.executionFailed(
                baseMsg + "\n\nHint: run `container system start` (System tab) and retry."
            )
        }
    }

    public func systemStart() async throws -> CLIResult {
        let res = try await runRaw(args: ["system", "start"], timeout: 180)
        return try ensureOk(res)
    }

    public func systemStop() async throws -> CLIResult {
        let res = try await runRaw(args: ["system", "stop"], timeout: 120)
        return try ensureOk(res)
    }

    public func systemVersion() async throws -> String {
        let res = try ensureOk(await runRaw(args: ["system", "version", "--format", "json"]))
        return res.stdout
    }
}
