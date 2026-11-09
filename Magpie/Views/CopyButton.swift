import SwiftUI
import UIKit

/// 把一段文字放进剪贴板，按完一秒半里显示「已复制」。
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
        // 放在列表行里时只有按钮本身响应点击，不是整行。
        .buttonStyle(.borderless)
    }
}
