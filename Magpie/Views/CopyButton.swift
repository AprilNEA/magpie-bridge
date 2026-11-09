import SwiftUI
import UIKit

/// Puts text on the pasteboard and shows "Copied" for a second and a half after the tap.
struct CopyButton: View {
    let text: String

    @State private var copied = false

    var body: some View {
        Button(copied ? "已复制" : "复制") {
            UIPasteboard.general.string = text
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        }
        // Inside a list row only the button itself responds to taps, not the whole row.
        .buttonStyle(.borderless)
    }
}
