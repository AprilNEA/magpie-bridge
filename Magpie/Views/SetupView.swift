import SwiftUI

/// The web /me page's "Setup": pick a tool and a model, then copy or share the config snippet.
struct SetupView: View {
    let session: Session

    @State private var target = SetupTarget.claudeCode
    @State private var model: ModelEntry?
    @State private var withKey = false

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
                            LabeledContent("模型") {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(model?.id ?? "未选择")
                                        .font(.callout.monospaced())
                                        .accessibilityIdentifier("setup.model")
                                    if let model, model.label != model.id {
                                        Text(model.label).font(.caption)
                                    }
                                }
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            }
                        }
                        Toggle("在配置里填入我的密钥", isOn: $withKey)
                    } footer: {
                        Text(withKey ? target.note + "片段里带着你的密钥，别发给别人。" : target.note)
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
                            HStack(spacing: 16) {
                                Text(block.title)
                                Spacer()
                                ShareLink(item: block.text) {
                                    Label("分享", systemImage: "square.and.arrow.up")
                                        .labelStyle(.iconOnly)
                                }
                                .font(.caption)
                                CopyButton(text: block.text)
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
        // A pushed page hides the search field until pulled down by default; there may be dozens
        // of models, so show the field right away.
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
