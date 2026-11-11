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

public struct StatusBadge: View {
    public let state: String
    public let isRunning: Bool

    public init(state: String, isRunning: Bool) {
        self.state = state
        self.isRunning = isRunning
    }

    private var dotColor: Color {
        if isRunning {
            return .green
        }
        let lower = state.lowercased()
        if lower.contains("paused") || lower.contains("starting") {
            return .orange
        }
        if lower.contains("error") || lower.contains("dead") {
            return .red
        }
        return .secondary
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(state.isEmpty ? "unknown" : state.capitalized)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(dotColor.opacity(0.12))
        )
    }
}
