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
import ContainerManagerCore

public struct ContainersTab: View {
    @ObservedObject var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var hasSelection: Bool {
        viewModel.selectedContainerId != nil
    }

    private var isSelectedRunning: Bool {
        viewModel.selectedContainer?.isRunning == true
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Action Toolbar
            HStack(spacing: 8) {
                Button {
                    viewModel.refreshContainers()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Button {
                    viewModel.showRunSheet = true
                } label: {
                    Label("Run…", systemImage: "plus.circle")
                }

                Divider()
                    .frame(height: 18)

                Button {
                    if let cid = viewModel.selectedContainerId {
                        viewModel.startContainer(id: cid)
                    }
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .disabled(!hasSelection || isSelectedRunning)

                Button {
                    if let cid = viewModel.selectedContainerId {
                        viewModel.stopContainer(id: cid)
                    }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(!hasSelection || !isSelectedRunning)

                Button {
                    if let cid = viewModel.selectedContainerId {
                        viewModel.promptRestartContainer(id: cid)
                    }
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise.circle")
                }
                .disabled(!hasSelection)

                Button {
                    if let cid = viewModel.selectedContainerId {
                        viewModel.promptRemoveContainer(id: cid)
                    }
                } label: {
                    Label("Remove…", systemImage: "trash")
                }
                .disabled(!hasSelection)

                Divider()
                    .frame(height: 18)

                Button {
                    if let cid = viewModel.selectedContainerId {
                        viewModel.fetchLogs(id: cid)
                    }
                } label: {
                    Label("Logs", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(!hasSelection)

                Button {
                    if let cid = viewModel.selectedContainerId {
                        viewModel.inspectContainer(id: cid)
                    }
                } label: {
                    Label("Inspect", systemImage: "info.circle")
                }
                .disabled(!hasSelection)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Containers Table or Empty State
            if viewModel.containers.isEmpty {
                EmptyStateView(
                    icon: "shippingbox",
                    title: "No Containers Found",
                    description: "No containers are currently present on this system. You can launch one using the Run button above or using the CLI: `container run -d alpine`.",
                    actionTitle: "Run Container…"
                ) {
                    viewModel.showRunSheet = true
                }
            } else {
                Table(viewModel.containers, selection: $viewModel.selectedContainerId) {
                    TableColumn("Name / ID") { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.displayName)
                                .font(.system(size: 13, weight: .semibold))
                            if !c.name.isEmpty && c.name != c.id {
                                Text(c.id.prefix(12))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .width(min: 140, ideal: 180)

                    TableColumn("Image") { c in
                        Text(c.image)
                            .font(.system(size: 12))
                    }
                    .width(min: 160, ideal: 220)

                    TableColumn("State") { c in
                        StatusBadge(state: c.state, isRunning: c.isRunning)
                    }
                    .width(min: 90, ideal: 110)

                    TableColumn("IP Address") { c in
                        Text(c.ip.isEmpty ? "—" : c.ip)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(c.ip.isEmpty ? .secondary : .primary)
                    }
                    .width(min: 100, ideal: 120)

                    TableColumn("OS / Arch") { c in
                        Text(c.osArch.isEmpty ? "—" : c.osArch)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .width(min: 90, ideal: 110)
                }
                .contextMenu(forSelectionType: ContainerInfo.ID.self) { items in
                    if let cid = items.first {
                        let c = viewModel.containers.first { $0.id == cid }
                        let isRunning = c?.isRunning == true

                        if !isRunning {
                            Button {
                                viewModel.startContainer(id: cid)
                            } label: {
                                Label("Start Container", systemImage: "play.fill")
                            }
                        } else {
                            Button {
                                viewModel.stopContainer(id: cid)
                            } label: {
                                Label("Stop Container", systemImage: "stop.fill")
                            }
                        }

                        Button {
                            viewModel.promptRestartContainer(id: cid)
                        } label: {
                            Label("Restart Container", systemImage: "arrow.clockwise")
                        }

                        Divider()

                        Button {
                            viewModel.fetchLogs(id: cid)
                        } label: {
                            Label("View Logs", systemImage: "doc.text.magnifyingglass")
                        }

                        Button {
                            viewModel.inspectContainer(id: cid)
                        } label: {
                            Label("Inspect Details", systemImage: "info.circle")
                        }

                        Divider()

                        Button(role: .destructive) {
                            viewModel.promptRemoveContainer(id: cid)
                        } label: {
                            Label("Remove Container", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}
