import SwiftUI
import LlamaPadCore

struct ModelsView: View {
    @ObservedObject var model: ServiceModel
    var onImport: () -> Void
    @State private var pendingRemoval: ModelFile?

    var body: some View {
        PageLayout("Your GGUF models, stored on this iPad.") {
            Surface {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        SectionHeading(title: "Model library", detail: "\(model.models.count) \(model.models.count == 1 ? "model" : "models") · \(totalSize) on disk")
                        Spacer()
                        Button("Import GGUF", systemImage: "plus", action: onImport)
                            .buttonStyle(.borderedProminent).foregroundStyle(LlamaStyle.onAccent).disabled(!model.canEdit)
                    }
                    if model.importing {
                        HStack(spacing: 12) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Importing model…").font(.subheadline.weight(.medium))
                                Text(model.importingName).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }.padding(.vertical, 8)
                    } else if model.models.isEmpty {
                        ContentUnavailableView {
                            Label("Make room for an idea", systemImage: "square.stack.3d.up")
                        } description: {
                            Text("Download a GGUF model, then import it from Files. Larger models need more memory, regardless of their active parameter count.")
                        } actions: {
                            Button("Choose a GGUF file", action: onImport).buttonStyle(.bordered)
                        }
                    }
                    if model.configuration.mode == .node {
                        InfoNote(text: "RPC nodes use the model on your Mac. This library is for running an inference server directly on the iPad.", symbol: "desktopcomputer")
                    } else if model.snapshot.isActive {
                        InfoNote(text: "Stop the service to switch, import, or remove models.", symbol: "lock")
                    }
                }
            }
            ForEach(model.models) { file in
                Surface {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "cube.transparent").font(.title).foregroundStyle(LlamaStyle.accent)
                                .padding(12).background(LlamaStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
                            VStack(alignment: .leading, spacing: 7) {
                                Text(file.name).font(.headline).textSelection(.enabled)
                                Text(file.sizeDescription).font(.subheadline).foregroundStyle(.secondary)
                                if let header = file.header {
                                    Text("GGUF v\(header.version) · \(header.tensorCount) tensors").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Label("Unreadable GGUF header", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Spacer(minLength: 0)
                            if file.url.path == model.configuration.modelPath {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(LlamaStyle.accent).accessibilityLabel("Selected model")
                            }
                        }
                        HStack {
                            Button(file.url.path == model.configuration.modelPath ? "Selected" : "Use this model") { model.selectModel(file) }
                                .buttonStyle(.bordered).disabled(!model.canEdit || file.header == nil || file.url.path == model.configuration.modelPath)
                            Spacer()
                            Button("Remove", systemImage: "trash", role: .destructive) { pendingRemoval = file }
                                .buttonStyle(.borderless).disabled(!model.canEdit)
                        }
                    }
                }
            }
            InfoNote(text: "You can also copy models into LlamaPad → Models in Files. Model files are excluded from iCloud backup. File size does not include runtime memory or context buffers.", symbol: "folder")
            Button("Refresh library", systemImage: "arrow.clockwise") { model.refreshModels() }.disabled(!model.canEdit)
        }
        .confirmationDialog("Remove this model?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }), titleVisibility: .visible) {
            Button("Remove from iPad", role: .destructive) {
                if let file = pendingRemoval { model.removeModel(file) }
                pendingRemoval = nil
            }
            Button("Keep model", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("\(pendingRemoval?.fileName ?? "This model") will be deleted from LlamaPad. The original file is unaffected.")
        }
    }
    private var totalSize: String {
        ByteCountFormatter.string(fromByteCount: model.models.reduce(0) { $0 + $1.byteCount }, countStyle: .file)
    }
}
