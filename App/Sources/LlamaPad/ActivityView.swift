import SwiftUI
import LlamaPadCore

struct ActivityView: View {
    @ObservedObject var model: ServiceModel
    @State private var logSearch = ""
    var body: some View {
        PageLayout("Device health, measured performance, and runtime details.") {
            Surface {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { SectionHeading(title: "Device health"); Spacer(); StatusBadge(title: model.statusTitle, state: model.snapshot.state) }
                    LabeledContent("GPU", value: model.snapshot.gpuName)
                    LabeledContent("Performance cores", value: "\(model.snapshot.performanceCores)")
                    LabeledContent("Available app allocation", value: LlamaStyle.memory(model.snapshot.availableMemory))
                    LabeledContent(model.configuration.mode == .node && model.snapshot.isActive ? "RPC buffers" : "App footprint", value: LlamaStyle.memory(model.snapshot.allocatedMemory))
                    LabeledContent("Temperature", value: LlamaStyle.thermal(model.snapshot.thermalState))
                    LabeledContent("Low Power Mode", value: model.snapshot.lowPowerMode ? "On" : "Off")
                    if model.snapshot.thermalState >= 2 || model.snapshot.lowPowerMode {
                        InfoNote(text: "Let the iPad cool and turn off Low Power Mode before measuring performance.", symbol: "thermometer.medium", color: .orange)
                    }
                }.font(.subheadline)
            }
            if model.configuration.mode == .server {
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeading(title: "Measure, then tune", detail: "One warmup and three timed requests. Prompt and generation speeds are measured separately.")
                        ViewThatFits(in: .horizontal) {
                            HStack { benchmarkButton; comparisonButton }
                            VStack(alignment: .leading) { benchmarkButton; comparisonButton }
                        }
                        if model.benchmarking { ProgressView(model.comparing ? "Comparing batch sizes…" : "Measuring performance…") }
                        if !model.benchmark.isEmpty { Text(model.benchmark).font(.subheadline).monospacedDigit().textSelection(.enabled) }
                        InfoNote(text: "Disconnect other clients before measuring. Batch comparison restarts the server between settings and finishes stopped, with the original settings restored.")
                    }
                }
            }
            if !model.benchmarkRecords.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "Saved measurements", detail: "Results are saved in LlamaPad/Benchmarks.json in Files.")
                    ForEach(model.benchmarkRecords.reversed()) { record in
                        Surface {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(record.model).font(.headline).lineLimit(2)
                                HStack(spacing: 24) {
                                    rate("Prompt", record.promptTokensPerSecond)
                                    rate("Generation", record.generationTokensPerSecond)
                                }
                                Text("\(record.samples) runs · micro batch \(record.microBatch) · \(record.date.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                                if record.model == model.selectedModel?.fileName {
                                    Button("Use this micro batch size") { model.useBenchmark(record) }.buttonStyle(.bordered).disabled(!model.canEdit)
                                }
                            }
                        }
                    }
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        SectionHeading(title: "Diagnostics")
                        Spacer()
                        ShareLink(item: model.diagnosticReport) { Label("Share", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                    }
                    LabeledContent("llama.cpp", value: String(model.snapshot.revision.prefix(12))).font(.caption)
                    DisclosureGroup("Runtime log") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Filter log", text: $logSearch).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                            if filteredLog.isEmpty {
                                Text(model.snapshot.logs.isEmpty ? "Logs will appear when you start a service." : "No matching log entries.").font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                Text(filteredLog).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }
                        }.padding(.top, 12)
                    }
                }
            }
        }
    }
    private var benchmarkButton: some View {
        Button("Measure speed", systemImage: "speedometer") { model.runBenchmark() }.buttonStyle(.borderedProminent).foregroundStyle(LlamaStyle.onAccent).disabled(!canMeasure)
    }
    private var comparisonButton: some View {
        Button("Compare batch sizes", systemImage: "chart.bar.xaxis") { model.compareBatchSizes() }.buttonStyle(.bordered).disabled(!canMeasure)
    }
    private var canMeasure: Bool { model.snapshot.state == "running" && !model.benchmarking && model.snapshot.thermalState < 2 }
    private var filteredLog: String {
        model.snapshot.logs.suffix(100).filter { logSearch.isEmpty || $0.localizedCaseInsensitiveContains(logSearch) }.joined(separator: "\n")
    }
    private func rate(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(String(format: "%.1f tok/s", value)).font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
        }.accessibilityElement(children: .combine)
    }
}
