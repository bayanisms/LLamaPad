import SwiftUI
import UIKit
import LlamaPadCore

struct SettingsView: View {
    @ObservedObject var model: ServiceModel
    @State private var preset = PerformancePreset.balanced
    @State private var confirmCache = false
    @State private var confirmKey = false
    @State private var portText = ""
    @FocusState private var editingPort: Bool
    var body: some View {
        Form {
            if !model.canEdit {
                Section { InfoNote(text: "Stop the service before changing settings.", symbol: "lock") }
            }
            Section {
                Picker("Connection", selection: $model.configuration.connection) {
                    ForEach(ConnectionMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                LabeledContent("Port") {
                    TextField("Port", text: $portText).keyboardType(.numberPad).focused($editingPort)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 160)
                }
                    .onChange(of: portText) { _, value in
                        if let port = Int(value) { model.configuration.port = port }
                    }
                if Int(portText).map({ !(1024...65535).contains($0) }) ?? true {
                    Text("Choose a port between 1024 and 65535.").font(.footnote).foregroundStyle(.orange)
                }
            } header: { Text("Service") } footer: { Text("Settings save automatically. Your API key is stored in the iPad’s Keychain.") }
                .disabled(!model.canEdit)
            if model.configuration.mode == .server {
                Section("Model") {
                    Picker("Selected model", selection: Binding(get: { model.configuration.modelPath }, set: { path in
                        if let file = model.models.first(where: { $0.url.path == path }) { model.selectModel(file) }
                    })) {
                        Text("Choose a model").tag("")
                        ForEach(model.models.filter { $0.header != nil }) { Text($0.name).tag($0.url.path) }
                    }
                    LabeledContent("API model name") {
                        TextField("API model name", text: $model.configuration.modelAlias)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().multilineTextAlignment(.trailing)
                    }
                }.disabled(!model.canEdit)
                Section {
                    Picker("Starting point", selection: $preset) {
                        ForEach(PerformancePreset.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Button("Apply preset for this iPad") { model.applyPreset(preset) }
                    Stepper("Context: \(model.configuration.contextSize.formatted()) tokens", value: $model.configuration.contextSize, in: 512...32768, step: 512)
                } header: { Text("Performance") } footer: { Text("Presets adapt to this iPad. Larger context needs more memory; a higher batch size mainly helps prompt processing.") }
                    .disabled(!model.canEdit)
            } else {
                Section {
                    Stepper("Buffer budget: \(LlamaStyle.memory(UInt64(model.configuration.nodeMemoryMiB) * 1_048_576))", value: $model.configuration.nodeMemoryMiB, in: 512...12288, step: 512)
                    Toggle("Cache received weights", isOn: $model.configuration.rpcCache)
                    LabeledContent("Cached weights on disk", value: LlamaStyle.memory(model.cacheBytes))
                    Button("Refresh cache size", systemImage: "arrow.clockwise") { model.refreshCacheSize() }
                    Button("Clear cached weights", systemImage: "trash", role: .destructive) { confirmCache = true }
                        .disabled(model.clearingCache || model.cacheBytes == 0)
                } header: { Text("RPC node") } footer: { Text("The buffer budget leaves room for iPadOS and temporary work. Cached weights speed up future connections; they do not increase generation speed.") }
                    .disabled(!model.canEdit)
            }
            Section {
                DisclosureGroup("Advanced performance") {
                    if model.configuration.mode == .server {
                        Stepper("GPU layers: \(model.configuration.gpuLayers == 999 ? "All" : String(model.configuration.gpuLayers))", value: $model.configuration.gpuLayers, in: 0...999)
                        Picker("Batch size", selection: $model.configuration.batchSize) {
                            ForEach([128, 256, 512, 1024, 2048], id: \.self) { Text("\($0)").tag($0) }
                        }.onChange(of: model.configuration.batchSize) { _, size in
                            model.configuration.microBatchSize = min(size, model.configuration.microBatchSize)
                        }
                        Picker("Micro batch", selection: $model.configuration.microBatchSize) {
                            ForEach([32, 64, 128, 256, 512].filter { $0 <= model.configuration.batchSize }, id: \.self) { Text("\($0)").tag($0) }
                        }
                        Picker("Flash Attention", selection: $model.configuration.flashAttention) {
                            Text("Automatic").tag("auto"); Text("On").tag("on"); Text("Off").tag("off")
                        }.onChange(of: model.configuration.flashAttention) { _, mode in
                            if mode != "on" { model.configuration.kvCacheType = "f16" }
                        }
                        Picker("KV cache", selection: $model.configuration.kvCacheType) {
                            Text("F16").tag("f16"); Text("Q8_0 · lower memory").tag("q8_0")
                        }.onChange(of: model.configuration.kvCacheType) { _, type in
                            if type == "q8_0" { model.configuration.flashAttention = "on" }
                        }
                    }
                    Stepper("CPU threads: \(model.configuration.threads)", value: $model.configuration.threads, in: 1...16)
                    Stepper("Memory reserve: \(LlamaStyle.memory(UInt64(model.configuration.memoryReserveMiB) * 1_048_576))", value: $model.configuration.memoryReserveMiB, in: 512...4096, step: 256)
                }
            } footer: { Text("Metal acceleration and chip-specific kernels are selected automatically. Use Activity to measure changes on this model and iPad.") }
                .disabled(!model.canEdit)
            if model.configuration.mode == .server {
                Section {
                    LabeledContent("API key") {
                        SecureField("API key", text: $model.configuration.apiKey)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().multilineTextAlignment(.trailing)
                    }
                    HStack {
                        CopyButton(value: model.configuration.apiKey, label: "Copy key")
                        Spacer()
                        Button("Generate new key") { confirmKey = true }
                    }
                } header: { Text("API access") } footer: { Text("Network clients must send this key. After rotating it, update your connected apps.") }
                    .disabled(!model.canEdit)
            }
            Section("About") {
                LabeledContent("LlamaPad", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                LabeledContent("Runtime", value: String(model.snapshot.revision.prefix(12)))
                LabeledContent("GPU", value: model.snapshot.gpuName)
            }
        }
        .formStyle(.grouped)
        .onAppear { portText = String(model.configuration.port); model.refreshCacheSize() }
        .onChange(of: model.configuration.port) { _, value in
            if !editingPort { portText = String(value) }
        }
        .onChange(of: model.configuration.mode) { _, _ in
            editingPort = false
            portText = String(model.configuration.port)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }
        .confirmationDialog("Clear cached RPC weights?", isPresented: $confirmCache, titleVisibility: .visible) {
            Button("Clear cached weights", role: .destructive) { model.clearRPCCache() }
        } message: { Text("The Mac will send the weights again on its next connection. Imported models and conversations are kept.") }
        .confirmationDialog("Generate a new API key?", isPresented: $confirmKey, titleVisibility: .visible) {
            Button("Generate new key", role: .destructive) { model.configuration.apiKey = UUID().uuidString + UUID().uuidString }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Apps using the current key will need the new one before they can connect again.") }
    }
}
