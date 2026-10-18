import Foundation

public struct RuntimeTelemetry: Codable, Sendable {
    public var timestamp: Double
    public var cpuSeconds: Double
    public var cpuCores: Int
    public var appMemory: UInt64
    public var uptime: Double
    public var bytesReceived: UInt64
    public var bytesSent: UInt64
    public var graphCalls: UInt64
    public var dispatchMilliseconds: Double
    public var connectedClients: Int
    public var allocationLimit: UInt64
    public var gpuCommands: UInt64?
    public var gpuMilliseconds: Double?
}

public struct TelemetryRate: Sendable {
    public var cpuFraction: Double = 0
    public var receiveBytesPerSecond: Double = 0
    public var sendBytesPerSecond: Double = 0
    public var graphsPerSecond: Double = 0
    public var dispatchMilliseconds: Double = 0
    public var gpuMilliseconds: Double?
    public init() {}
    public init(previous: RuntimeTelemetry?, current: RuntimeTelemetry) {
        guard let previous, current.timestamp > previous.timestamp, current.uptime >= previous.uptime else { return }
        let seconds = current.timestamp - previous.timestamp
        cpuFraction = min(1, max(0, (current.cpuSeconds - previous.cpuSeconds) / seconds / Double(max(1, current.cpuCores))))
        if current.bytesReceived >= previous.bytesReceived {
            receiveBytesPerSecond = Double(current.bytesReceived - previous.bytesReceived) / seconds
        }
        if current.bytesSent >= previous.bytesSent {
            sendBytesPerSecond = Double(current.bytesSent - previous.bytesSent) / seconds
        }
        let graphs = current.graphCalls >= previous.graphCalls ? current.graphCalls - previous.graphCalls : 0
        graphsPerSecond = Double(graphs) / seconds
        if graphs > 0 { dispatchMilliseconds = max(0, current.dispatchMilliseconds - previous.dispatchMilliseconds) / Double(graphs) }
        if let count = current.gpuCommands, let oldCount = previous.gpuCommands,
           let milliseconds = current.gpuMilliseconds, let oldMilliseconds = previous.gpuMilliseconds,
           count >= oldCount, milliseconds >= oldMilliseconds {
            gpuMilliseconds = count > oldCount ? (milliseconds - oldMilliseconds) / Double(count - oldCount) : 0
        }
    }
}

public struct TelemetryPoint: Identifiable {
    public let id = UUID()
    public let time: Double
    public let cpu: Double
    public let receive: Double
    public let send: Double
    public let graphs: Double
    public let gpuMilliseconds: Double?
    public let thermalState: Int
    public init(time: Double, rate: TelemetryRate, thermalState: Int = 0) {
        self.time = time; cpu = rate.cpuFraction; receive = rate.receiveBytesPerSecond
        send = rate.sendBytesPerSecond; graphs = rate.graphsPerSecond
        gpuMilliseconds = rate.gpuMilliseconds
        self.thermalState = min(3, max(0, thermalState))
    }
}

public enum TelemetryDisplay {
    public static func transferRate(_ bytesPerSecond: Double) -> String {
        let value = bytesPerSecond.isFinite ? max(0, bytesPerSecond) : 0
        if value < 1024 { return String(format: "%.0f B/s", value > 0 ? max(1, value) : 0) }
        if value < 1_048_576 { return String(format: "%.1f KiB/s", value / 1024) }
        if value < 1_073_741_824 { return String(format: "%.1f MiB/s", value / 1_048_576) }
        return String(format: "%.2f GiB/s", value / 1_073_741_824)
    }
}
