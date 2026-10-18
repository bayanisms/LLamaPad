import SwiftUI
import LlamaPadCore

struct ServerWorkspace: View {
    @ObservedObject var model: ServiceModel
    var keyboardVisible: Bool
    var onImport: () -> Void
    var onStop: () -> Void
    @State private var section = "Chat"
    @State private var chatLoading = true
    @State private var chatFailure: String?
    @State private var externalURL: URL?
    @State private var exportURL: URL?
    @State private var dismissKeyboardToken = 0
    @State private var reload = UUID()
    private let sections = ["Chat", "Settings", "Connect"]

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(model: model, mode: .server, onStop: onStop)
            Picker("Server workspace", selection: $section) {
                ForEach(sections, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal, 24).padding(.bottom, 16)
                .accessibilityIdentifier("server-section")
            Divider()
            if model.configuration.mode != .server {
                OtherServiceView(model: model, mode: .server, onStop: onStop)
            } else if section == "Settings" {
                SettingsView(model: model)
            } else if section == "Connect" {
                ConnectionView(model: model)
            } else if model.snapshot.state == "running" {
                if let chatFailure {
                    ContentUnavailableView {
                        Label("Reopen chat", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                    } description: { Text(chatFailure) } actions: {
                        Button("Reload chat") { self.chatFailure = nil; reload = UUID() }.buttonStyle(.borderedProminent)
                    }
                } else {
                    ChatWebView(port: model.configuration.port, apiKey: model.configuration.apiKey, dismissKeyboardToken: dismissKeyboardToken,
                        loading: $chatLoading, failure: $chatFailure, externalURL: $externalURL, exportURL: $exportURL)
                        .id("\(model.configuration.port)-\(reload)")
                        .overlay {
                            if chatLoading {
                                ProgressView("Opening chat…").frame(maxWidth: .infinity, maxHeight: .infinity).background(LlamaStyle.background)
                            }
                        }
                }
            } else {
                PageLayout("Chat and an OpenAI-compatible API, powered by this iPad.") {
                    Surface {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack(spacing: 16) {
                                BrandMark(size: 72)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(model.snapshot.state == "starting" ? "Preparing your model…" : "A home for your conversations.")
                                        .font(.system(.title2, design: .rounded, weight: .bold))
                                    Text("Start a model to open llama.cpp chat.").foregroundStyle(.secondary)
                                }
                            }
                            if model.snapshot.isActive { ProgressView(value: model.snapshot.progress).tint(LlamaStyle.accent) }
                            if let file = model.selectedModel {
                                Label(file.name, systemImage: "cube").font(.headline)
                                Text("\(file.sizeDescription) · \(model.configuration.contextSize.formatted()) token context").font(.subheadline).foregroundStyle(.secondary)
                            } else { Button("Import GGUF model", systemImage: "square.and.arrow.down", action: onImport).buttonStyle(.bordered) }
                            Button("Model & server settings", systemImage: "slider.horizontal.3") { section = "Settings" }.buttonStyle(.bordered)
                        }
                    }
                    Surface {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeading(title: "Your full chat workspace", detail: "Conversations stay on this iPad, with the same design in light and dark mode.")
                            Label("System prompts, sampling, and generation settings", systemImage: "slider.horizontal.3")
                            Label("Streaming, Markdown, code, and message editing", systemImage: "text.bubble")
                            Label("Conversation search, branching, and import / export", systemImage: "bubble.left.and.bubble.right")
                            Text("Attachments and tools appear according to the loaded model’s capabilities. External tools require their own services.").font(.footnote).foregroundStyle(.secondary)
                        }.font(.subheadline)
                    }
                }
            }
        }
        .background(LlamaStyle.background)
        .toolbar {
            if keyboardVisible {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") {
                        dismissKeyboardToken += 1
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }.accessibilityIdentifier("chat-hide-keyboard")
                }
            }
        }
        .onChange(of: model.snapshot.state) { _, state in if state != "running" { chatFailure = nil } }
        .sheet(isPresented: Binding(get: { externalURL != nil }, set: { if !$0 { externalURL = nil } })) {
            if let externalURL { InAppBrowser(url: externalURL).ignoresSafeArea() }
        }
        .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
            if let exportURL { ChatExport(url: exportURL) }
        }
    }
}

struct WorkspaceHeader: View {
    @ObservedObject var model: ServiceModel
    let mode: ServiceMode
    var onStop: () -> Void
    private var selected: Bool { model.configuration.mode == mode }
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(mode == .server ? (selected && model.snapshot.state == "running" ? model.configuration.modelAlias : "Inference on this iPad") : "Metal compute worker")
                    .font(.headline).lineLimit(1)
                Text(selected ? "\(model.configuration.connection.title) · Port \(String(model.configuration.port))" : "Run one service at a time")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            StatusBadge(title: selected ? model.statusTitle : "Standby", state: selected ? model.snapshot.state : "stopped")
            if selected && (model.snapshot.isActive || model.comparing) {
                Button("Stop", systemImage: "stop.fill", action: onStop)
                    .buttonStyle(.bordered).disabled(model.snapshot.state == "stopping")
                    .accessibilityIdentifier("service-primary-action")
            } else {
                Button(mode == .server ? "Start server" : "Start node", systemImage: "play.fill") { model.changeMode(mode); model.start() }
                    .buttonStyle(.borderedProminent).foregroundStyle(LlamaStyle.onAccent)
                    .disabled(!selected || !model.canStart || !model.canEdit)
                    .accessibilityIdentifier("service-primary-action")
            }
        }.padding(.horizontal, 24).padding(.vertical, 16)
    }
}

struct OtherServiceView: View {
    @ObservedObject var model: ServiceModel
    let mode: ServiceMode
    var onStop: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("\(model.configuration.mode == .node ? "RPC Node" : "Inference Server") is active", systemImage: "arrow.triangle.swap")
        } description: {
            Text("Stop the current service to use \(mode.title). Its settings will be kept.")
        } actions: {
            Button("Stop \(model.configuration.mode.title)", action: onStop).buttonStyle(.bordered)
        }
    }
}
