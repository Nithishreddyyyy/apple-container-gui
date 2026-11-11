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

public struct MainView: View {
    @StateObject private var viewModel = AppViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Container Manager")
                        .font(.system(size: 16, weight: .bold))
                    Text("Native graphical frontend for Apple's `container` runtime")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    StatusBadge(
                        state: "System: \(viewModel.systemStatus.status)",
                        isRunning: viewModel.systemStatus.isRunning
                    )

                    Button {
                        viewModel.refreshAll()
                    } label: {
                        Label("Refresh All", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isBusy)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Segmented Tab Selector
            HStack {
                Picker("", selection: $viewModel.currentTab) {
                    ForEach(AppTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Main Content Area with Split Console Output
            VSplitView {
                // Tab Content
                Group {
                    switch viewModel.currentTab {
                    case .containers:
                        ContainersTab(viewModel: viewModel)
                    case .images:
                        ImagesTab(viewModel: viewModel)
                    case .system:
                        SystemTab(viewModel: viewModel)
                    }
                }
                .frame(minHeight: 240)

                // Bottom Command Output Pane
                CommandOutputView(viewModel: viewModel)
                    .frame(minHeight: 100, idealHeight: 140, maxHeight: 300)
            }

            Divider()

            // Status Bar
            HStack {
                if viewModel.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                }

                Text(viewModel.statusMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                Text("Apple Silicon / macOS")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onAppear {
            viewModel.refreshAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshAllRequested)) { _ in
            viewModel.refreshAll()
        }
        .sheet(isPresented: $viewModel.showRunSheet) {
            RunContainerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showPullSheet) {
            PullImageSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showInspectSheet) {
            InspectSheet(target: viewModel.inspectTarget, content: viewModel.inspectContent)
        }
        .sheet(isPresented: $viewModel.showLogsSheet) {
            LogsSheet(target: viewModel.logsTarget, content: viewModel.logsContent)
        }
        .alert(item: $viewModel.activeAlert) { alert in
            if alert.isDestructive {
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    primaryButton: .destructive(Text(alert.primaryButtonTitle), action: alert.primaryAction),
                    secondaryButton: .cancel()
                )
            } else {
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    primaryButton: .default(Text(alert.primaryButtonTitle), action: alert.primaryAction),
                    secondaryButton: .cancel()
                )
            }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
