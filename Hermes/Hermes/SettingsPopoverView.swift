import SwiftUI

// MARK: - Popover Root View

struct SettingsPopoverView: View {
    @AppStorage("refinementIntensity") var intensity: Int = 1
    @AppStorage("ollamaModel") var modelName: String = "llama3:8b"
    @State private var isHoveringQuit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.7))
                Text("Hermes")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("v1.2")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()
                .padding(.horizontal, 16)

            // Content
            VStack(alignment: .leading, spacing: 18) {
                // Refinement Intensity Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Refinement")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    VStack(spacing: 4) {
                        IntensityRow(
                            icon: "waveform",
                            title: "Raw",
                            subtitle: "No modifications",
                            tag: 0,
                            selectedTag: $intensity
                        )
                        IntensityRow(
                            icon: "pencil.line",
                            title: "Editor",
                            subtitle: "Cleans speech & punctuation",
                            tag: 1,
                            selectedTag: $intensity
                        )
                        IntensityRow(
                            icon: "doc.text",
                            title: "Writer",
                            subtitle: "Professional rewrite",
                            tag: 2,
                            selectedTag: $intensity
                        )
                    }
                }

                // Model Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    ModelPicker(modelName: $modelName)

                    Text("Run: ollama pull \(modelName)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 18)

            Divider()
                .padding(.horizontal, 16)

            // Footer
            HStack {
                Spacer()
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                            .font(.system(size: 10, weight: .medium))
                        Text("Quit")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(isHoveringQuit ? .red : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(isHoveringQuit ? Color.red.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHoveringQuit = hovering
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 300)
    }
}

// MARK: - Intensity Row

struct IntensityRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tag: Int
    @Binding var selectedTag: Int
    @State private var isHovering = false

    private var isSelected: Bool { tag == selectedTag }

    var body: some View {
        Button(action: { selectedTag = tag }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .white : .primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary.opacity(0.7))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                        ? Color.accentColor.opacity(0.85)
                        : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Model Picker

struct ModelPicker: View {
    @Binding var modelName: String
    @State private var isCustom = false
    @FocusState private var isFieldFocused: Bool
    
    private struct ModelOption: Identifiable {
        let id: String
        let label: String
        let detail: String
    }
    
    private let models: [ModelOption] = [
        ModelOption(id: "gemma3:1b",    label: "Gemma 3 1B",    detail: "~1 GB · Fastest"),
        ModelOption(id: "llama3.2:1b",  label: "Llama 3.2 1B",  detail: "~1.3 GB · Fast"),
        ModelOption(id: "llama3.2:3b",  label: "Llama 3.2 3B",  detail: "~2 GB · Recommended"),
        ModelOption(id: "phi4-mini",    label: "Phi-4 Mini",     detail: "~2.5 GB · Great quality"),
        ModelOption(id: "gemma3:4b",    label: "Gemma 3 4B",    detail: "~3 GB · High quality"),
        ModelOption(id: "llama3:8b",    label: "Llama 3 8B",    detail: "~5 GB · Best quality"),
    ]
    
    private var isKnownModel: Bool {
        models.contains { $0.id == modelName }
    }
    
    var body: some View {
        VStack(spacing: 6) {
            Picker(selection: Binding(
                get: { isKnownModel ? modelName : "__custom__" },
                set: { newValue in
                    if newValue == "__custom__" {
                        isCustom = true
                    } else {
                        isCustom = false
                        modelName = newValue
                    }
                }
            )) {
                ForEach(models) { model in
                    HStack {
                        Text(model.label)
                        Spacer()
                        Text(model.detail)
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .tag(model.id)
                }
                Divider()
                Text("Custom…")
                    .tag("__custom__")
            } label: {
                EmptyView()
            }
            .labelsHidden()
            
            if isCustom || !isKnownModel {
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    TextField("e.g. mistral:7b", text: $modelName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .focused($isFieldFocused)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(8)
                .onAppear { isFieldFocused = true }
            }
        }
    }
}

#Preview {
    SettingsPopoverView()
        .frame(width: 300)
}
