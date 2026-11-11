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

public struct SystemTab: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var versionCopied = UIState(false)

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                // Service Control Card
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("System Service Daemon", systemImage: "server.rack")
                            .font(.headline)
                        Spacer()
                        StatusBadge(
                            state: viewModel.systemStatus.status,
                            isRunning: viewModel.systemStatus.isRunning
                        )
                    }

                    Text("The container system service coordinates Linux virtualization, apiserver XPC endpoints, vmnet network bridges, and container lifecycle on macOS.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            viewModel.refreshSystem()
                        } label: {
                            Label("Refresh Status", systemImage: "arrow.clockwise")
                        }

                        Button {
                            viewModel.promptStartSystem()
                        } label: {
                            Label("Start System", systemImage: "play.fill")
                        }
                        .disabled(viewModel.systemStatus.isRunning)

                        Button {
                            viewModel.promptStopSystem()
                        } label: {
                            Label("Stop System", systemImage: "stop.fill")
                        }
                        .disabled(!viewModel.systemStatus.isRunning)
                    }
                    .padding(.top, 4)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )

                // Environment & Paths Card
                if !viewModel.systemStatus.installRoot.isEmpty || !viewModel.systemStatus.appRoot.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Runtime Paths", systemImage: "folder")
                            .font(.headline)

                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                            if !viewModel.systemStatus.appRoot.isEmpty {
                                GridRow {
                                    Text("Application Root:")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Text(viewModel.systemStatus.appRoot)
                                        .font(.system(.subheadline, design: .monospaced))
                                }
                            }
                            if !viewModel.systemStatus.installRoot.isEmpty {
                                GridRow {
                                    Text("Install Root:")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Text(viewModel.systemStatus.installRoot)
                                        .font(.system(.subheadline, design: .monospaced))
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                }

                // Version Details Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("CLI & Subsystem Version Details", systemImage: "info.circle")
                            .font(.headline)
                        Spacer()
                        Button(versionCopied.value ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(viewModel.systemVersionText, forType: .string)
                            versionCopied.value = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                versionCopied.value = false
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                    }

                    ScrollView([.horizontal, .vertical]) {
                        Text(viewModel.systemVersionText.isEmpty ? "(version details unavailable)" : viewModel.systemVersionText)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 140, maxHeight: 220)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
            .padding(16)
        }
    }
}
