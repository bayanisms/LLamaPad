import Foundation

public enum ServiceMode: String, Codable, CaseIterable, Sendable {
    case server, node
    public var title: String { self == .server ? "Inference server" : "RPC node" }
    public var port: Int { self == .server ? 8080 : 50052 }
}

public enum ConnectionMode: String, Codable, CaseIterable, Sendable {
    case usb, network
    public var title: String { self == .usb ? "USB cable" : "Local network" }
    public var bindAddress: String { self == .usb ? "127.0.0.1" : "0.0.0.0" }
}

public enum PerformancePreset: String, Codable, CaseIterable, Sendable {
    case balanced, throughput, lowMemory
    public var title: String {
        switch self {
        case .balanced: "Balanced"
        case .throughput: "Prompt throughput"
        case .lowMemory: "Lower memory"
        }
    }
}

public struct RuntimeConfiguration: Codable, Equatable, Sendable {
    public var mode: ServiceMode = .server
    public var connection: ConnectionMode = .usb
    public var port: Int = 8080
    public var modelPath: String = ""
    public var modelAlias: String = "llamapad"
    public var contextSize: Int = 4096
    public var batchSize: Int = 512
    public var microBatchSize: Int = 128
    public var threads: Int = 4
    public var gpuLayers: Int = 999
    public var flashAttention: String = "auto"
    public var kvCacheType: String = "f16"
    public var apiKey: String = ""
    public var cacheDirectory: String = ""
    public var rpcCache: Bool = true
    public var nodeMemoryMiB: Int = 8192
    public var memoryReserveMiB: Int = 1536

    public init() {}

    public mutating func apply(_ preset: PerformancePreset) {
        threads = 4
        gpuLayers = 999
        switch preset {
        case .balanced:
            contextSize = 4096; batchSize = 512; microBatchSize = 128
            flashAttention = "auto"; kvCacheType = "f16"
        case .throughput:
            contextSize = 4096; batchSize = 1024; microBatchSize = 256
            flashAttention = "auto"; kvCacheType = "f16"
        case .lowMemory:
            contextSize = 2048; batchSize = 256; microBatchSize = 64
            flashAttention = "on"; kvCacheType = "q8_0"
        }
    }

    public mutating func apply(_ preset: PerformancePreset, device: DeviceProfile) {
        apply(preset)
        threads = device.recommendedThreads
        memoryReserveMiB = device.reserveMiB
        nodeMemoryMiB = device.nodeBudgetMiB
        if preset == .balanced {
            microBatchSize = device.balancedMicroBatch
        } else if preset == .throughput {
            microBatchSize = device.throughputMicroBatch
        }
    }

    public func validated() throws -> RuntimeConfiguration {
        guard (1024...65535).contains(port) else { throw ConfigurationError("Choose a port between 1024 and 65535.") }
        guard (1...16).contains(threads) else { throw ConfigurationError("CPU threads must be between 1 and 16.") }
        guard (256...32768).contains(contextSize) else { throw ConfigurationError("Context must be between 256 and 32,768 tokens.") }
        guard (32...2048).contains(batchSize), (32...batchSize).contains(microBatchSize) else {
            throw ConfigurationError("Micro batch must be between 32 and the batch size; batch size must be 32–2048.")
        }
        guard ["auto", "on", "off"].contains(flashAttention), ["f16", "q8_0"].contains(kvCacheType) else {
            throw ConfigurationError("Unsupported attention or KV cache setting.")
        }
        guard kvCacheType == "f16" || flashAttention == "on" else {
            throw ConfigurationError("Quantized KV cache requires Flash Attention on. Use F16 if the model does not support it.")
        }
        guard (0...999).contains(gpuLayers) else { throw ConfigurationError("GPU layers must be between 0 and 999.") }
        guard (512...12288).contains(nodeMemoryMiB), (512...16384).contains(memoryReserveMiB) else {
            throw ConfigurationError("Choose a node budget of 512–12,288 MiB and a reserve of at least 512 MiB.")
        }
        if mode == .server {
            guard modelPath.lowercased().hasSuffix(".gguf") else { throw ConfigurationError("Import and select a GGUF model first.") }
            guard !modelAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConfigurationError("Enter a model name.") }
            guard connection != .network || apiKey.count >= 16 else {
                throw ConfigurationError("Use an API key of at least 16 characters for network serving.")
            }
        }
        return self
    }

    public var forwardCommand: String { "iproxy --local \(port):\(port)" }
    public func macCommand(address: String) -> String {
        let host = connection == .usb ? "127.0.0.1" : NetworkHost.authority(address)
        if mode == .node {
            let endpoint = "\(host):\(port)"
            let argument = host.hasPrefix("[") ? "'\(endpoint)'" : endpoint
            return "./build-mac/bin/llama-server -m /path/to/model.gguf --rpc \(argument) --split-mode layer -ngl 999 -c 4096"
        }
        return "http://\(host):\(port)/v1"
    }
}

public struct ConfigurationError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct RuntimeSnapshot: Codable, Sendable {
    public var state: String = "stopped"
    public var message: String = "Ready to start"
    public var progress: Double = 0
    public var logs: [String] = []
    public var availableMemory: UInt64 = 0
    public var physicalMemory: UInt64 = 0
    public var allocatedMemory: UInt64 = 0
    public var thermalState: Int = 0
    public var backend: String = ""
    public var revision: String = ""
    public var metalPatch: String?
    public var launchID: String?
    public var gpuName: String = ""
    public var gpuFamily: Int = 0
    public var performanceCores: Int = 4
    public var tensorHardware: Bool = false
    public var lowPowerMode: Bool = false
    public init() {}
    public var telemetry: RuntimeTelemetry?
    public var isActive: Bool { ["starting", "running", "stopping"].contains(state) }
}
