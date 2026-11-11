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

public struct CommandOutputView: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var copied = UIState(false)

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Command Output", systemImage: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    viewModel.copyOutput()
                    copied.value = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied.value = false
                    }
                } label: {
                    Label(copied.value ? "Copied" : "Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)

                Button {
                    viewModel.clearOutput()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Console output area
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(viewModel.commandOutput.isEmpty ? "(no command output yet)" : viewModel.commandOutput)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(viewModel.commandOutput.isEmpty ? .secondary : .primary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .textSelection(.enabled)
                            .id("console_bottom")
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: viewModel.commandOutput) {
                    withAnimation {
                        proxy.scrollTo("console_bottom", anchor: .bottom)
                    }
                }
            }
        }
    }
}
