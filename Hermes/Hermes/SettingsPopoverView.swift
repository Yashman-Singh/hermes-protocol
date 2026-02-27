import SwiftUI

// MARK: - Popover Root View

struct SettingsPopoverView: View {
    @AppStorage("refinementIntensity") var intensity: Int = 1
    @AppStorage("ollamaModel") var modelName: String = "llama3:8b"
    @State private var isHoveringQuit = false
    @FocusState private var isModelFieldFocused: Bool

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
                Text("v1.0")
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

                    HStack(spacing: 8) {
                        Image(systemName: "cpu")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        TextField("Model name", text: $modelName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .focused($isModelFieldFocused)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)

                    Text("Ensure Ollama is running with this model")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))
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
        .onAppear {
            // Prevent text field from auto-focusing
            isModelFieldFocused = false
        }
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

#Preview {
    SettingsPopoverView()
        .frame(width: 300)
}
