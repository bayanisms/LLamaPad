import Foundation

/// Conservative starting points, not a substitute for benchmarking a model.
public struct DeviceProfile: Sendable {
    public let recommendedThreads: Int
    public let reserveMiB: Int
    public let nodeBudgetMiB: Int
    public let balancedMicroBatch: Int
    public let throughputMicroBatch: Int
    public let supportsTensorHardware: Bool

    public init(snapshot: RuntimeSnapshot) {
        recommendedThreads = max(1, min(snapshot.performanceCores, 8))
        let available = Int(snapshot.availableMemory / 1_048_576)
        let physical = Int(snapshot.physicalMemory / 1_048_576)
        reserveMiB = physical <= 8192 ? 1024 : 1536
        // Keep additional space for Metal scratch buffers and transfer staging.
        let usable = max(0, available - reserveMiB)
        nodeBudgetMiB = max(512, min(12288, (usable * 3 / 4 / 256) * 256))
        supportsTensorHardware = snapshot.tensorHardware
        if available < 4096 {
            balancedMicroBatch = 64
            throughputMicroBatch = 128
        } else if snapshot.gpuFamily >= 9 && available >= 8192 {
            balancedMicroBatch = 256
            throughputMicroBatch = 512
        } else {
            balancedMicroBatch = 128
            throughputMicroBatch = 256
        }
    }
}

public struct BenchmarkRecord: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var model: String
    public var gpu: String
    public var revision: String
    public var context: Int
    public var batch: Int
    public var microBatch: Int
    public var threads: Int
    public var cache: String
    public var attention: String
    public var promptTokensPerSecond: Double
    public var generationTokensPerSecond: Double
    public var samples: Int
    public var thermalState: Int
    public var lowPowerMode: Bool

    public init(configuration: RuntimeConfiguration, snapshot: RuntimeSnapshot, prompt: [Double], generation: [Double]) {
        model = URL(fileURLWithPath: configuration.modelPath).lastPathComponent
        gpu = snapshot.gpuName
        revision = snapshot.revision
        context = configuration.contextSize; batch = configuration.batchSize
        microBatch = configuration.microBatchSize; threads = configuration.threads
        cache = configuration.kvCacheType; attention = configuration.flashAttention
        promptTokensPerSecond = Self.median(prompt)
        generationTokensPerSecond = Self.median(generation)
        samples = min(prompt.count, generation.count)
        thermalState = snapshot.thermalState
        lowPowerMode = snapshot.lowPowerMode
    }

    public static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
