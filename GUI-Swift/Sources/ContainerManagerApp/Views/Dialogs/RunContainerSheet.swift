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

public struct RunContainerSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var image = UIState("")
    @StateObject private var name = UIState("")
    @StateObject private var validationError = UIState<String?>(nil)

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Run Container")
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

            Form {
                Section {
                    TextField("Image Reference:", text: $image.value, prompt: Text("e.g. docker.io/library/alpine:latest"))
                        .textFieldStyle(.roundedBorder)

                    TextField("Container Name (optional):", text: $name.value, prompt: Text("e.g. my-app"))
                        .textFieldStyle(.roundedBorder)
                } footer: {
                    Text("Starts a detached container instance using Apple's container virtualization runtime.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let err = validationError.value {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(20)

            Divider()

            // Footer buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Run Container") {
                    runAction()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(image.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 460)
    }

    private func runAction() {
        let cleanImage = image.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.value.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try Validation.validateImageRef(cleanImage)
            if !cleanName.isEmpty {
                try Validation.validateIdentifier(cleanName, kind: "container name")
            }
            validationError.value = nil
            viewModel.runContainer(image: cleanImage, name: cleanName)
            dismiss()
        } catch {
            validationError.value = error.localizedDescription
        }
    }
}
