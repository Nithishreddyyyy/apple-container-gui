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

/// A clean observable container for local view state that does not require
/// compiler-level macro expansion plugins, ensuring full compatibility across
/// standalone Command Line Tools and Xcode environments.
@MainActor
public final class UIState<T>: ObservableObject {
    @Published public var value: T

    public init(_ initialValue: T) {
        self.value = initialValue
    }
}
