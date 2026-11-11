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

public struct ImagesTab: View {
    @ObservedObject var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var hasSelection: Bool {
        viewModel.selectedImageId != nil
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Action Toolbar
            HStack(spacing: 8) {
                Button {
                    viewModel.refreshImages()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Button {
                    viewModel.showPullSheet = true
                } label: {
                    Label("Pull…", systemImage: "arrow.down.circle")
                }

                Divider()
                    .frame(height: 18)

                Button {
                    if let sel = viewModel.selectedImage {
                        viewModel.promptRemoveImage(ref: sel.reference)
                    }
                } label: {
                    Label("Remove…", systemImage: "trash")
                }
                .disabled(!hasSelection)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Images Table or Empty State
            if viewModel.images.isEmpty {
                EmptyStateView(
                    icon: "opticaldisc",
                    title: "No Images Found",
                    description: "No container images are downloaded yet. Pull your first image from Docker Hub or any OCI registry.",
                    actionTitle: "Pull Image…"
                ) {
                    viewModel.showPullSheet = true
                }
            } else {
                Table(viewModel.images, selection: $viewModel.selectedImageId) {
                    TableColumn("Repository / Name") { img in
                        HStack(spacing: 8) {
                            Image(systemName: "opticaldisc")
                                .foregroundColor(.accentColor)
                            Text(img.name)
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .width(min: 180, ideal: 260)

                    TableColumn("Tag") { img in
                        Text(img.tag.isEmpty ? "latest" : img.tag)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.15))
                            )
                    }
                    .width(min: 80, ideal: 110)

                    TableColumn("OS / Arch") { img in
                        Text(img.osArch.isEmpty ? "—" : img.osArch)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .width(min: 90, ideal: 120)

                    TableColumn("Size") { img in
                        Text(img.size.isEmpty ? "—" : img.size)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .width(min: 80, ideal: 100)
                }
                .contextMenu(forSelectionType: ImageInfo.ID.self) { items in
                    if let iid = items.first, let img = viewModel.images.first(where: { $0.id == iid }) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(img.reference, forType: .string)
                        } label: {
                            Label("Copy Reference", systemImage: "doc.on.doc")
                        }

                        Button {
                            viewModel.pullImage(ref: img.reference)
                        } label: {
                            Label("Update / Re-pull", systemImage: "arrow.down.circle")
                        }

                        Divider()

                        Button(role: .destructive) {
                            viewModel.promptRemoveImage(ref: img.reference)
                        } label: {
                            Label("Remove Image", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}
