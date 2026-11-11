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

@main
public struct ContainerManagerApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            MainView()
                .frame(minWidth: 800, minHeight: 540)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 960, height: 680)
        .commands {
            SidebarCommands()

            CommandGroup(replacing: .appInfo) {
                Button("About Container Manager") {
                    showAboutPanel()
                }
            }

            CommandGroup(after: .newItem) {
                Button("Refresh All") {
                    NotificationCenter.default.post(name: .refreshAllRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    private func showAboutPanel() {
        let alert = NSAlert()
        alert.messageText = "Container Manager"
        alert.informativeText = "Native macOS SwiftUI GUI for Apple's container CLI.\n\nA seamless dashboard for container lifecycle, OCI image management, and virtualization system service control on Apple Silicon."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension Notification.Name {
    public static let refreshAllRequested = Notification.Name("refreshAllRequested")
}
