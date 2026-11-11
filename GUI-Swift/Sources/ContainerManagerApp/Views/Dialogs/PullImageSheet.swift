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

public struct PullImageSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var ref = UIState("")
    @StateObject private var validationError = UIState<String?>(nil)

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Pull Image")
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
                    TextField("Image Reference:", text: $ref.value, prompt: Text("e.g. docker.io/library/alpine:latest"))
                        .textFieldStyle(.roundedBorder)
                } footer: {
                    Text("Pulls the specified image layer manifest from the OCI container registry.")
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

            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Pull Image") {
                    pullAction()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(ref.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 440)
    }

    private func pullAction() {
        let cleanRef = ref.value.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try Validation.validateImageRef(cleanRef)
            validationError.value = nil
            viewModel.pullImage(ref: cleanRef)
            dismiss()
        } catch {
            validationError.value = error.localizedDescription
        }
    }
}
