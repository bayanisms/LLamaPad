import SwiftUI
import Charts
import LlamaPadCore

struct NodeWorkspace: View {
    @ObservedObject var model: ServiceModel
    var onStop: () -> Void
    @State private var section = "Monitor"
    @State private var confirmRestart = false
    private let sections = ["Monitor", "Controls", "Connect"]
    private var telemetry: RuntimeTelemetry? { model.snapshot.telemetry }
    private var budget: UInt64 { telemetry?.allocationLimit ?? 0 }
    private var allocated: UInt64 { model.snapshot.isActive && model.configuration.mode == .node ? model.snapshot.allocatedMemory : 0 }
    private var historyEnd: Double { model.telemetryHistory.last?.time ?? telemetry?.timestamp ?? 0 }
    private var history: [TelemetryPoint] { model.telemetryHistory.filter { $0.time >= historyEnd - 60 && $0.time <= historyEnd } }
    private var transferPeak: Double { history.map { max($0.receive, $0.send) }.max() ?? 0 }
    private var transferUnit: (divisor: Double, label: String) {
        if transferPeak >= 1_048_576 { return (1_048_576, "MiB/s") }
        if transferPeak >= 1024 { return (1024, "KiB/s") }
        return (1, "B/s")
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(model: model, mode: .node, onStop: onStop)
            Picker("Node workspace", selection: $section) {
                ForEach(sections, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal, 24).padding(.bottom, 16).accessibilityIdentifier("node-section")
            Divider()
            if model.configuration.mode != .node {
                OtherServiceView(model: model, mode: .node, onStop: onStop)
            } else if section == "Controls" {
                SettingsView(model: model)
            } else if section == "Connect" {
                ConnectionView(model: model)
            } else {
                monitor
            }
        }.background(LlamaStyle.background)
        .confirmationDialog("Restart RPC node?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Restart node", role: .destructive) { model.restart() }.accessibilityIdentifier("confirm-restart-node")
        } message: { Text("The Mac coordinator will disconnect and buffers will be released. Restart its inference process after the node is ready.") }
    }

    private var monitor: some View {
        PageLayout("Live device health and worker activity. Updated twice a second.") {
            Surface {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.snapshot.state == "running" ? ((telemetry?.connectedClients ?? 0) > 0 ? "Coordinator connected" : "Ready for a coordinator") : "Your iPad’s compute, shared.")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                            Text(model.snapshot.message).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "point.3.connected.trianglepath.dotted").font(.largeTitle).foregroundStyle(LlamaStyle.accent).accessibilityHidden(true)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 18) { connectionStatus; uptimeLabel; restartButton }
                        VStack(alignment: .leading, spacing: 12) { connectionStatus; uptimeLabel; restartButton }
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                gauge("RPC buffers", value: budget > 0 ? Double(allocated) / Double(budget) : 0,
                    display: LlamaStyle.memory(allocated), detail: budget > 0 ? "of \(LlamaStyle.memory(budget)) effective budget" : "Budget applies when running", symbol: "memorychip")
                gauge("App CPU", value: model.telemetryRate.cpuFraction,
                    display: model.telemetryRate.cpuFraction.formatted(.percent.precision(.fractionLength(0))),
                    detail: "Share of all \(telemetry?.cpuCores ?? 0) CPU cores", symbol: "cpu")
                gauge("Thermal pressure", value: Double(model.snapshot.thermalState) / 3,
                    display: LlamaStyle.thermal(model.snapshot.thermalState), detail: "iPadOS thermal state", symbol: "thermometer.medium",
                    color: model.snapshot.thermalState >= 2 ? .orange : .green)
                gauge("Battery", value: max(0, Double(model.batteryLevel)),
                    display: model.batteryLevel < 0 ? "Unavailable" : Double(model.batteryLevel).formatted(.percent.precision(.fractionLength(0))),
                    detail: model.batteryLevel < 0 ? "Battery status unavailable" : model.batteryCharging ? "Connected to power" : (model.snapshot.lowPowerMode ? "Low Power Mode on" : "On battery"), symbol: model.batteryCharging ? "bolt.batteryblock" : "battery.75percent")
            }
            Surface {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeading(title: "Transfer activity", detail: "RPC payload and length framing · last 60 seconds")
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 36) { receiveMetric; sendMetric }
                        VStack(alignment: .leading, spacing: 16) { receiveMetric; sendMetric }
                    }
                    Chart(history) { point in
                        LineMark(x: .value("Seconds ago", point.time - historyEnd), y: .value(transferUnit.label, point.receive / transferUnit.divisor))
                            .foregroundStyle(by: .value("Direction", "Receive"))
                        LineMark(x: .value("Seconds ago", point.time - historyEnd), y: .value(transferUnit.label, point.send / transferUnit.divisor))
                            .foregroundStyle(by: .value("Direction", "Send"))
                    }
                    .chartForegroundStyleScale(["Receive": LlamaStyle.accent, "Send": Color.blue])
                    .chartXScale(domain: -60...0, range: .plotDimension(padding: 5))
                    .chartYScale(domain: 0...max(1, transferPeak / transferUnit.divisor * 1.15))
                    .chartPlotStyle { plot in plot.clipped() }
                    .chartXAxis { AxisMarks(values: [-60, -30, 0]) }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
                    .chartXAxisLabel("Seconds ago").chartYAxisLabel(transferUnit.label).frame(height: 160)
                    .accessibilityLabel("RPC transfer history over the last sixty seconds")
                    .accessibilityIdentifier("transfer-history")
                    Text("Received \(LlamaStyle.memory(telemetry?.bytesReceived ?? 0)) · Sent \(LlamaStyle.memory(telemetry?.bytesSent ?? 0))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            NodeDeviceHistory(points: history, end: historyEnd, rate: model.telemetryRate, snapshot: model.snapshot)
            Surface {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeading(title: "Compute activity", detail: "Graphs dispatched to this worker, including cached graph reuse")
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 36) { graphMetric; dispatchMetric }
                        VStack(alignment: .leading, spacing: 16) { graphMetric; dispatchMetric }
                    }
                    NodeHistoryChart(points: history, end: historyEnd, value: { $0.graphs },
                        domain: 0...max(1, (history.map(\.graphs).max() ?? 0) * 1.15))
                        .accessibilityLabel("RPC graph dispatch history over the last sixty seconds")
                        .accessibilityIdentifier("compute-history")
                    Text("\((telemetry?.graphCalls ?? 0).formatted()) graphs this session. Dispatch measures wall time spent submitting graphs, including waits; GPU work runs asynchronously. Token speed is measured on the Mac coordinator.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Device monitoring")
                    LabeledContent("Metal device", value: model.snapshot.gpuName)
                    LabeledContent("App memory footprint", value: LlamaStyle.memory(telemetry?.appMemory ?? 0))
                    LabeledContent("Available app allocation", value: LlamaStyle.memory(model.snapshot.availableMemory))
                    LabeledContent("Physical memory", value: LlamaStyle.memory(model.snapshot.physicalMemory))
                    LabeledContent("Low Power Mode", value: model.snapshot.lowPowerMode ? "On" : "Off")
                    if model.snapshot.thermalState >= 2 || model.snapshot.lowPowerMode {
                        InfoNote(text: "Let the iPad cool and disable Low Power Mode for better sustained throughput.", symbol: "thermometer.medium", color: .orange)
                    }
                }.font(.subheadline)
            }
        }
    }
    private var connectionStatus: some View {
        Label("\(telemetry?.connectedClients ?? 0) / 1 coordinator", systemImage: "network").font(.subheadline)
    }
    private var uptimeLabel: some View {
        Label(Duration.seconds(telemetry?.uptime ?? 0).formatted(.time(pattern: .hourMinuteSecond)), systemImage: "clock").font(.subheadline).monospacedDigit()
    }
    private var restartButton: some View {
        Button("Restart node", systemImage: "arrow.clockwise") { confirmRestart = true }
            .buttonStyle(.bordered).disabled(model.snapshot.state != "running").accessibilityIdentifier("restart-node")
    }
    private var receiveMetric: some View { metric("Receive", rate(model.telemetryRate.receiveBytesPerSecond), "arrow.down") }
    private var sendMetric: some View { metric("Send", rate(model.telemetryRate.sendBytesPerSecond), "arrow.up") }
    private var graphMetric: some View { metric("Graph dispatch", String(format: "%.1f /s", model.telemetryRate.graphsPerSecond), "waveform.path") }
    private var dispatchMetric: some View { metric("Mean dispatch", String(format: "%.2f ms", model.telemetryRate.dispatchMilliseconds), "timer") }
    private func rate(_ value: Double) -> String { TelemetryDisplay.transferRate(value) }
    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }.accessibilityElement(children: .combine)
    }
    private func gauge(_ title: String, value: Double, display: String, detail: String, symbol: String, color: Color = LlamaStyle.accent) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Gauge(value: min(1, max(0, value))) { Text(title) } currentValueLabel: { Image(systemName: symbol) }
                        .gaugeStyle(.accessoryCircularCapacity).tint(color)
                        .accessibilityLabel(title).accessibilityValue(display)
                    Spacer()
                }
                Text(display).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
