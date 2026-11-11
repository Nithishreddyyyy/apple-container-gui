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

import SwiftUI
import AppKit
import ContainerManagerCore

public enum AppTab: String, CaseIterable, Identifiable {
    case containers = "Containers"
    case images = "Images"
    case system = "System"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .containers: return "shippingbox"
        case .images: return "opticaldisc"
        case .system: return "gearshape.2"
        }
    }
}

public struct AppAlert: Identifiable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let isDestructive: Bool
    public let primaryButtonTitle: String
    public let primaryAction: () -> Void

    public init(
        title: String,
        message: String,
        isDestructive: Bool = false,
        primaryButtonTitle: String = "OK",
        primaryAction: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.isDestructive = isDestructive
        self.primaryButtonTitle = primaryButtonTitle
        self.primaryAction = primaryAction
    }
}

@MainActor
public final class AppViewModel: ObservableObject {
    private var service: ContainerService?

    @Published public var currentTab: AppTab = .containers
    @Published public var containers: [ContainerInfo] = []
    @Published public var images: [ImageInfo] = []
    @Published public var systemStatus: SystemStatus = SystemStatus()
    @Published public var systemVersionText: String = ""

    @Published public var isBusy: Bool = false
    @Published public var statusMessage: String = "Starting…"
    @Published public var commandOutput: String = ""

    @Published public var selectedContainerId: String? = nil
    @Published public var selectedImageId: String? = nil

    // Sheets & Dialogs
    @Published public var showRunSheet: Bool = false
    @Published public var showPullSheet: Bool = false
    @Published public var showInspectSheet: Bool = false
    @Published public var inspectContent: String = ""
    @Published public var inspectTarget: String = ""
    @Published public var showLogsSheet: Bool = false
    @Published public var logsContent: String = ""
    @Published public var logsTarget: String = ""
    @Published public var activeAlert: AppAlert? = nil
    @Published public var errorMessage: String? = nil

    public init(service: ContainerService? = nil) {
        if let s = service {
            self.service = s
        } else {
            do {
                self.service = try ContainerService()
            } catch {
                self.statusMessage = "Error: \(error.localizedDescription)"
                self.logText("ERROR: \(error.localizedDescription)")
            }
        }
    }

    public var selectedContainer: ContainerInfo? {
        guard let id = selectedContainerId else { return nil }
        return containers.first { $0.id == id }
    }

    public var selectedImage: ImageInfo? {
        guard let id = selectedImageId else { return nil }
        return images.first { $0.id == id }
    }

    // MARK: - Output Logging

    public func logText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if commandOutput.isEmpty {
                commandOutput = trimmed + "\n"
            } else {
                commandOutput += trimmed + "\n"
            }
        }
    }

    public func logResult(command: String, stdout: String, stderr: String) {
        logText("$ container \(command)")
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !out.isEmpty {
            logText(out)
        }
        if !err.isEmpty {
            logText("[stderr] \(err)")
        }
    }

    public func clearOutput() {
        commandOutput = ""
    }

    public func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commandOutput, forType: .string)
    }

    // MARK: - Safe Async Job Runner

    private func performJob(label: String, action: @escaping () async throws -> Void) {
        if isBusy {
            errorMessage = "Another operation is in progress. Please wait."
            return
        }

        isBusy = true
        statusMessage = "\(label)…"

        Task {
            do {
                guard let _ = self.service else {
                    throw ContainerCLIError.binaryNotFound("The `container` command was not found on PATH.")
                }
                try await action()
            } catch {
                let msg = error.localizedDescription
                self.logText("ERROR: \(msg)")
                self.statusMessage = "Error — see Command Output"
                self.errorMessage = msg
            }
            self.isBusy = false
        }
    }

    // MARK: - Refresh All

    public func refreshAll() {
        performJob(label: "Refreshing") {
            guard let svc = self.service else { return }

            var errors: [String] = []

            // System Status
            do {
                let st = try await svc.systemStatus()
                self.systemStatus = st
            } catch {
                self.systemStatus = SystemStatus(status: "unknown")
                errors.append("system status: \(error.localizedDescription)")
            }

            // System Version
            do {
                let ver = try await svc.systemVersion()
                self.systemVersionText = ver
            } catch {
                self.systemVersionText = "(version unavailable)"
            }

            // Containers
            do {
                let cList = try await svc.listContainers()
                let cRaw = try await svc.runRaw(args: ["list", "--all"])
                self.containers = cList
                self.logResult(command: "list --all", stdout: cRaw.stdout, stderr: cRaw.stderr)
            } catch {
                errors.append("containers: \(error.localizedDescription)")
            }

            // Images
            do {
                let iList = try await svc.listImages()
                let iRaw = try await svc.runRaw(args: ["image", "list"])
                self.images = iList
                self.logResult(command: "image list", stdout: iRaw.stdout, stderr: iRaw.stderr)
            } catch {
                errors.append("images: \(error.localizedDescription)")
            }

            if !errors.isEmpty {
                for e in errors {
                    self.logText("ERROR: \(e)")
                }
                self.statusMessage = "Ready (some refreshes failed — see output)"
            } else {
                let n = self.containers.count
                let m = self.images.count
                self.statusMessage = "Ready — \(n) container(s), \(m) image(s)"
            }
        }
    }

    public func refreshContainers() {
        performJob(label: "Refreshing containers") {
            try await self.loadContainers()
        }
    }

    public func refreshImages() {
        performJob(label: "Refreshing images") {
            try await self.loadImages()
        }
    }

    public func refreshSystem() {
        performJob(label: "Checking system status") {
            try await self.loadSystem()
        }
    }

    // Refresh within the current job so its busy guard still rejects unrelated actions.
    private func loadContainers() async throws {
        guard let svc = service else { return }
        let items = try await svc.listContainers()
        let raw = try await svc.runRaw(args: ["list", "--all"])
        containers = items
        logResult(command: "list --all", stdout: raw.stdout, stderr: raw.stderr)
        statusMessage = "Ready — \(items.count) container(s)"
    }

    private func loadImages() async throws {
        guard let svc = service else { return }
        let items = try await svc.listImages()
        let raw = try await svc.runRaw(args: ["image", "list"])
        images = items
        logResult(command: "image list", stdout: raw.stdout, stderr: raw.stderr)
        statusMessage = "Ready — \(items.count) image(s)"
    }

    private func loadSystem() async throws {
        guard let svc = service else { return }
        let st = try await svc.systemStatus()
        systemStatus = st
        do {
            systemVersionText = try await svc.systemVersion()
        } catch {
            systemVersionText = "(version unavailable while system is stopped)"
        }
        logText("$ container system status\n\(st.status)")
        statusMessage = "System: \(st.status)"
    }

    // MARK: - Container Operations

    public func startContainer(id: String) {
        performJob(label: "Starting \(id)") {
            guard let svc = self.service else { return }
            let res = try await svc.startContainer(id: id)
            self.logResult(command: "start \(id)", stdout: res.stdout, stderr: res.stderr)
            self.statusMessage = "Started \(id)"
            try await self.loadContainers()
        }
    }

    public func stopContainer(id: String) {
        performJob(label: "Stopping \(id)") {
            guard let svc = self.service else { return }
            let res = try await svc.stopContainer(id: id)
            self.logResult(command: "stop \(id)", stdout: res.stdout, stderr: res.stderr)
            self.statusMessage = "Stopped \(id)"
            try await self.loadContainers()
        }
    }

    public func promptRestartContainer(id: String) {
        activeAlert = AppAlert(
            title: "Restart Container",
            message: "Restart container '\(id)'? This will stop and then start it.",
            isDestructive: false,
            primaryButtonTitle: "Restart"
        ) { [weak self] in
            self?.restartContainer(id: id)
        }
    }

    public func restartContainer(id: String) {
        performJob(label: "Restarting \(id)") {
            guard let svc = self.service else { return }
            let res = try await svc.restartContainer(id: id)
            self.logResult(command: "restart \(id)", stdout: res.stdout, stderr: res.stderr)
            self.statusMessage = "Restarted \(id)"
            try await self.loadContainers()
        }
    }

    public func promptRemoveContainer(id: String) {
        activeAlert = AppAlert(
            title: "Remove Container",
            message: "Are you sure you want to remove container '\(id)'? This action cannot be undone.",
            isDestructive: true,
            primaryButtonTitle: "Remove"
        ) { [weak self] in
            self?.removeContainer(id: id)
        }
    }

    public func removeContainer(id: String, force: Bool = false) {
        performJob(label: "Removing \(id)") {
            guard let svc = self.service else { return }
            let res = try await svc.removeContainer(id: id, force: force)
            self.logResult(command: "rm \(id)", stdout: res.stdout, stderr: res.stderr)
            self.statusMessage = "Removed \(id)"
            if self.selectedContainerId == id {
                self.selectedContainerId = nil
            }
            try await self.loadContainers()
        }
    }

    public func fetchLogs(id: String, tail: Int = 200) {
        performJob(label: "Fetching logs for \(id)") {
            guard let svc = self.service else { return }
            let res = try await svc.containerLogs(id: id, tail: tail)
            self.logResult(command: "logs \(id)", stdout: res.stdout, stderr: res.stderr)
            self.logsTarget = id
            self.logsContent = res.stdout.isEmpty ? (res.stderr.isEmpty ? "(no log output)" : res.stderr) : res.stdout
            self.showLogsSheet = true
            self.statusMessage = "Logs for \(id)"
        }
    }

    public func inspectContainer(id: String) {
        performJob(label: "Inspecting \(id)") {
            guard let svc = self.service else { return }
            let out = try await svc.inspectContainer(id: id)
            self.logResult(command: "inspect \(id)", stdout: out, stderr: "")
            self.inspectTarget = id
            self.inspectContent = out
            self.showInspectSheet = true
            self.statusMessage = "Inspected \(id)"
        }
    }

    public func runContainer(image: String, name: String) {
        performJob(label: "Running \(image)") {
            guard let svc = self.service else { return }
            let res = try await svc.runContainer(image: image, name: name)
            self.logResult(command: "run --detach \(image)", stdout: res.stdout, stderr: res.stderr)
            self.statusMessage = "Container started"
            try await self.loadContainers()
        }
    }

    // MARK: - Image Operations

    public func pullImage(ref: String) {
        performJob(label: "Pulling \(ref)") {
            guard let svc = self.service else { return }
            let res = try await svc.pullImage(ref: ref)
            self.logResult(command: "image pull \(ref)", stdout: res.stdout, stderr: res.stderr)
            self.statusMessage = "Pulled \(ref)"
            try await self.loadImages()
        }
    }

    public func promptRemoveImage(ref: String) {
        activeAlert = AppAlert(
            title: "Remove Image",
            message: "Are you sure you want to remove image '\(ref)'?",
            isDestructive: true,
            primaryButtonTitle: "Remove"
        ) { [weak self] in
            self?.removeImage(ref: ref)
        }
    }

    public func removeImage(ref: String, force: Bool = false) {
        performJob(label: "Removing image \(ref)") {
            guard let svc = self.service else { return }
            let res = try await svc.removeImage(ref: ref, force: force)
            self.logResult(command: "image rm \(ref)", stdout: res.stdout, stderr: res.stderr)
            self.statusMessage = "Removed image \(ref)"
            if let sel = self.selectedImage, sel.reference == ref {
                self.selectedImageId = nil
            }
            try await self.loadImages()
        }
    }

    // MARK: - System Operations

    public func promptStartSystem() {
        activeAlert = AppAlert(
            title: "Start System Service",
            message: "Start the container system service? This may take a moment to initialize the virtualization daemon.",
            isDestructive: false,
            primaryButtonTitle: "Start System"
        ) { [weak self] in
            self?.startSystem()
        }
    }

    public func startSystem() {
        performJob(label: "Starting system service") {
            guard let svc = self.service else { return }
            let res = try await svc.systemStart()
            self.logResult(command: "system start", stdout: res.stdout, stderr: res.stderr)
            self.statusMessage = "System start requested"
            try await self.loadSystem()
        }
    }

    public func promptStopSystem() {
        activeAlert = AppAlert(
            title: "Stop System Service",
            message: "Stop the container system service? Running containers will be halted.",
            isDestructive: true,
            primaryButtonTitle: "Stop System"
        ) { [weak self] in
            self?.stopSystem()
        }
    }

    public func stopSystem() {
        performJob(label: "Stopping system service") {
            guard let svc = self.service else { return }
            let res = try await svc.systemStop()
            self.logResult(command: "system stop", stdout: res.stdout, stderr: res.stderr)
            self.statusMessage = "System stop requested"
            try await self.loadSystem()
        }
    }
}
