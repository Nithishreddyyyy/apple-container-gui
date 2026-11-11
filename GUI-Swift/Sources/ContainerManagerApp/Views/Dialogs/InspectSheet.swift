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

public struct InspectSheet: View {
    public let target: String
    public let content: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var copied = UIState(false)

    public init(target: String, content: String) {
        self.target = target
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Inspect: \(target)", systemImage: "info.circle")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Monospaced content
            ScrollView([.horizontal, .vertical]) {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
            }
            .background(Color(NSColor.textBackgroundColor))

            Divider()

            // Footer
            HStack {
                Button(copied.value ? "Copied!" : "Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                    copied.value = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied.value = false
                    }
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 550, minHeight: 400)
    }
}
