import SwiftUI
import LlamaPadCore

struct ConnectionView: View {
    @ObservedObject var model: ServiceModel
    var body: some View {
        PageLayout("A clear path from your Mac to this iPad.") {
            Surface {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeading(title: "Connection", detail: "\(model.configuration.mode.title) · Port \(model.configuration.port)")
                    Picker("Connection", selection: $model.configuration.connection) {
                        ForEach(ConnectionMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).disabled(!model.canEdit)
                    if model.configuration.connection == .network {
                        HStack {
                            TextField("iPad IP address or hostname", text: $model.networkAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                                .textFieldStyle(.roundedBorder).accessibilityLabel("iPad network address")
                            Button("Detect", systemImage: "wifi") { model.detectNetworkAddress() }.buttonStyle(.bordered)
                        }
                        if model.connectionHost == nil {
                            InfoNote(text: "Enter an IP address such as 192.168.1.20 or a hostname such as ipad.local.", color: .orange)
                        }
                        InfoNote(text: model.configuration.mode == .node ? "RPC has no authentication. Use a trusted private network." : "Network serving requires an API key and uses plain HTTP. Connect on a trusted private network.", symbol: "network")
                    }
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 24) {
                    SectionHeading(title: "Get connected")
                    if model.configuration.connection == .usb {
                        step(1, "Connect and trust", "Connect the iPad directly to the Mac with a data cable. Unlock it and trust the Mac when prompted.")
                        step(2, "Start USB forwarding", "Install libusbmuxd on your Mac if needed, then keep this command running in Terminal.")
                        CommandBlock(title: "Install once on your Mac", value: "brew install libusbmuxd")
                        CommandBlock(title: "USB forwarding", value: model.configuration.forwardCommand)
                    } else {
                        step(1, "Join the same network", "Connect the Mac and iPad to the same private network, then check the iPad address above.")
                    }
                    step(model.configuration.connection == .usb ? 3 : 2, "Start LlamaPad", "Start the \(model.configuration.mode == .node ? "node" : "server") from Overview. Keep the app open during use.")
                    if let command = model.connectionCommand {
                        CommandBlock(title: model.configuration.mode == .node ? "Run on your Mac" : "OpenAI-compatible base URL", value: command)
                        if model.configuration.mode == .node {
                            InfoNote(text: "Replace /path/to/model.gguf with your model file. Use a Mac llama.cpp build matching this app’s runtime revision; choose the device split for your available memory.")
                        } else {
                            LabeledContent("Model name", value: model.configuration.modelAlias).font(.subheadline)
                            CopyButton(value: model.configuration.apiKey, label: "Copy API key")
                        }
                    }
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Ready for your tools", systemImage: "app.connected.to.app.below.fill").font(.headline)
                    Text(model.configuration.mode == .server
                        ? "Use the base URL and model name in any client that supports an OpenAI-compatible API. Use your API key when the client asks for one."
                        : "Your Mac loads the GGUF and uses this iPad as a Metal worker. No model copy or import is needed in the iPad library.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)").font(.subheadline.bold()).foregroundStyle(LlamaStyle.accent)
                .frame(width: 30, height: 30).background(LlamaStyle.accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}
