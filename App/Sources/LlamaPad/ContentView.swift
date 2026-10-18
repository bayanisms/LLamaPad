import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LlamaPadCore

enum AppPage: String, CaseIterable, Identifiable {
    case server, node, models, activity
    var id: String { rawValue }
    var title: String {
        switch self { case .server: "Inference Server"; case .node: "RPC Node"; case .models: "Models"; case .activity: "Activity" }
    }
    var mode: ServiceMode? { self == .server ? .server : self == .node ? .node : nil }
    var symbol: String {
        switch self {
        case .server: "bubble.left.and.text.bubble.right"
        case .node: "point.3.connected.trianglepath.dotted"
        case .models: "square.stack.3d.up"
        case .activity: "waveform.path.ecg"
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: ServiceModel
    @State private var page: AppPage? = .server
    @State private var showImporter = false
    @State private var keyboardVisible = false
    @State private var confirmStop = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Section {
                    HStack(spacing: 12) {
                        BrandMark(size: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("LlamaPad").font(.system(.title3, design: .rounded, weight: .bold)).lineLimit(1).minimumScaleFactor(0.75)
                            Text("Your iPad, connected.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 14).listRowBackground(Color.clear)
                }
                Section {
                    ForEach(AppPage.allCases) { item in
                        NavigationLink(value: item) {
                            Label {
                                Text(item.title).foregroundStyle(page == item ? LlamaStyle.onAccent : Color.primary)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            } icon: {
                                Image(systemName: item.symbol).foregroundStyle(page == item ? LlamaStyle.onAccent : LlamaStyle.accent)
                            }.padding(.vertical, 5)
                        }
                            .accessibilityIdentifier("nav-\(item.rawValue)")
                    }
                }
            }
            .listStyle(.sidebar).navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if !keyboardVisible {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    StatusBadge(title: model.statusTitle, state: model.snapshot.state)
                    Text("\(model.configuration.mode.title) · \(model.configuration.connection.title)")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20)
                }
            }
            .navigationSplitViewColumnWidth(min: typeSize.isAccessibilitySize ? 300 : 230,
                ideal: typeSize.isAccessibilitySize ? 320 : 250, max: typeSize.isAccessibilitySize ? 380 : 290)
        } detail: {
            Group {
                switch page ?? .server {
                case .server: ServerWorkspace(model: model, keyboardVisible: keyboardVisible, onImport: { showImporter = true }, onStop: { confirmStop = true })
                case .node: NodeWorkspace(model: model, onStop: { confirmStop = true })
                case .models: ModelsView(model: model, onImport: { showImporter = true })
                case .activity: ActivityView(model: model)
                }
            }
            .navigationTitle((page ?? .server).title).navigationBarTitleDisplayMode(.inline)
        }
        .navigationSplitViewStyle(.balanced).tint(LlamaStyle.accent)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .onAppear {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--llamapad-smoke-node") || arguments.contains("--llamapad-rpc-node") { page = .node }
            else if arguments.contains("--llamapad-smoke-server") { page = .server }
            else { page = model.configuration.mode == .node ? .node : .server }
        }
        .onChange(of: page) { _, value in if let mode = value?.mode { model.changeMode(mode) } }
        .onChange(of: model.canEdit) { _, editable in
            if editable, let mode = page?.mode { model.changeMode(mode) }
        }
        .onChange(of: model.configuration) { _, _ in model.saveSettings() }
        .onChange(of: model.networkAddress) { _, _ in model.saveNetworkAddress() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data]) { result in
            switch result {
            case .success(let url): Task { await model.importModel(url) }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { model.error = error.localizedDescription }
            }
        }
        .confirmationDialog("Stop the service?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop service", role: .destructive) { model.stop() }.accessibilityIdentifier("confirm-stop-service")
            Button("Keep running", role: .cancel) {}
        } message: { Text("Connected requests will end. You can start it again from its workspace.") }
        .alert("Couldn't complete the action", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
