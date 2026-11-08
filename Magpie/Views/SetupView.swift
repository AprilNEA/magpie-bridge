import SwiftUI
import UIKit

/// 网页 /me 的「配置」：选工具和模型，复制配置片段。
struct SetupView: View {
    let session: Session

    @State private var target = SetupTarget.claudeCode
    @State private var model: ModelEntry?
    @State private var withKey = false
    @State private var copied: String?

    var body: some View {
        Form {
            if let info = session.info, let credential = session.credential {
                if info.readOnly {
                    Section {
                        Text("这个密钥只能查看用量，不能调用模型。")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Picker("工具", selection: $target) {
                            ForEach(SetupTarget.allCases) { target in
                                Text(target.title).tag(target)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("setup.target")
                        NavigationLink {
                            ModelPickerView(models: info.models, selection: $model)
                        } label: {
                            LabeledContent("模型", value: model?.id ?? "未选择")
                        }
                        Toggle("在配置里填入我的密钥", isOn: $withKey)
                    } footer: {
                        Text(target.note)
                    }
                    let blocks = SetupSnippet.blocks(
                        for: target, baseURL: credential.baseURL,
                        key: withKey ? credential.key : nil, model: model?.id)
                    ForEach(blocks) { block in
                        Section {
                            Text(block.text)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } header: {
                            HStack {
                                Text(block.title)
                                Spacer()
                                Button(copied == block.id ? "已复制" : "复制") {
                                    copy(block)
                                }
                                .font(.caption)
                                .textCase(nil)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("配置")
        .onChange(of: session.info?.models, initial: true) { _, models in
            guard let models else { return }
            if let model, models.contains(model) { return }
            model = session.info?.suggestedModel
        }
    }

    private func copy(_ block: SetupSnippet.Block) {
        UIPasteboard.general.string = block.text
        copied = block.id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copied == block.id {
                copied = nil
            }
        }
    }
}

struct ModelPickerView: View {
    let models: [ModelEntry]
    @Binding var selection: ModelEntry?

    @State private var filter = ""
    @Environment(\.dismiss) private var dismiss

    private var shown: [ModelEntry] {
        let filter = filter.trimmingCharacters(in: .whitespaces)
        guard !filter.isEmpty else { return models }
        return models.filter {
            $0.id.localizedCaseInsensitiveContains(filter)
                || $0.label.localizedCaseInsensitiveContains(filter)
        }
    }

    var body: some View {
        List(shown) { model in
            Button {
                selection = model
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.id).font(.callout.monospaced())
                        if model.label != model.id {
                            Text(model.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if model == selection {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
            .tint(.primary)
        }
        // 推入的页面默认把搜索框藏到下拉才出现；模型可能有几十个，直接露出来。
        .searchable(
            text: $filter, placement: .navigationBarDrawer(displayMode: .always),
            prompt: "筛选模型"
        )
        .navigationTitle("这个密钥可用的模型")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if models.isEmpty {
                ContentUnavailableView("这个密钥不能使用任何模型。", systemImage: "cpu")
            }
        }
    }
}
