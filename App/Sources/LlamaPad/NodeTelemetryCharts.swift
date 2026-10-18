import SwiftUI
import Charts
import LlamaPadCore

struct NodeHistoryChart: View {
    let points: [TelemetryPoint]
    let end: Double
    let value: (TelemetryPoint) -> Double?
    let domain: ClosedRange<Double>
    var color: Color = LlamaStyle.accent
    var thermal = false
    var unit = "Graphs/s"

    var body: some View {
        Chart(points) { point in
            if let sample = value(point) {
                LineMark(x: .value("Seconds ago", point.time - end), y: .value(unit, sample))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(thermal ? .stepEnd : .linear)
            }
        }
        .chartXScale(domain: -60...0, range: .plotDimension(padding: 5))
        .chartYScale(domain: domain, range: .plotDimension(padding: 5))
        .chartXAxis {
            AxisMarks(values: [-60, -30, 0]) { axis in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let seconds = axis.as(Int.self) { Text(seconds == 0 ? "Now" : "\(seconds)s") }
                }
            }
        }
        .chartYAxis {
            if thermal {
                AxisMarks(position: .leading, values: [0, 1, 2, 3]) { axis in
                    AxisGridLine()
                    AxisValueLabel {
                        if let state = axis.as(Int.self) { Text(LlamaStyle.thermal(state)).font(.caption2) }
                    }
                }
            } else {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
            }
        }
        .chartPlotStyle { plot in plot.clipped() }
        .frame(height: 145)
    }
}

struct NodeDeviceHistory: View {
    let points: [TelemetryPoint]
    let end: Double
    let rate: TelemetryRate
    let snapshot: RuntimeSnapshot

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
            historyCard("CPU history", value: rate.cpuFraction.formatted(.percent.precision(.fractionLength(1))),
                detail: "App CPU · share of all cores", identifier: "cpu-history") {
                NodeHistoryChart(points: points, end: end, value: { $0.cpu * 100 }, domain: 0...100, unit: "App CPU (%)")
            }
            historyCard("GPU history", value: gpuValue,
                detail: "Mean Metal command time · milliseconds", identifier: "gpu-history") {
                NodeHistoryChart(points: points, end: end, value: { $0.gpuMilliseconds },
                    domain: 0...max(1, (points.compactMap(\.gpuMilliseconds).max() ?? 0) * 1.15), color: .blue, unit: "GPU command time (ms)")
            }
            historyCard("Thermal history", value: LlamaStyle.thermal(snapshot.thermalState),
                detail: "iPadOS thermal pressure · last 60 seconds", identifier: "thermal-history") {
                NodeHistoryChart(points: points, end: end, value: { Double($0.thermalState) }, domain: 0...3,
                    color: snapshot.thermalState >= 2 ? .orange : .green, thermal: true, unit: "Thermal pressure")
            }
        }
        Text("GPU history measures completed inference command buffers, including any GPU waits. It is not whole-device GPU utilization. iPadOS provides thermal pressure rather than a temperature in °C.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private var gpuValue: String {
        guard (snapshot.telemetry?.gpuCommands ?? 0) > 0 else { return "Waiting for GPU work" }
        return rate.gpuMilliseconds.map { String(format: "%.2f ms", $0) } ?? "Sampling…"
    }

    private func historyCard<Plot: View>(_ title: String, value: String, detail: String, identifier: String,
                                         @ViewBuilder plot: () -> Plot) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.headline)
                Text(value).font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                plot().accessibilityLabel(title + ", last sixty seconds").accessibilityIdentifier(identifier)
            }
        }
    }
}
