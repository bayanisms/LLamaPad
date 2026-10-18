import Foundation
import SwiftUI
import UIKit
import Security
import Darwin
import LlamaPadCore
import LlamaNative

@MainActor
final class ServiceModel: ObservableObject {
    @Published var configuration = RuntimeConfiguration()
    @Published var snapshot = RuntimeSnapshot()
    @Published var models: [ModelFile] = []
    @Published var importing = false
    @Published var importingName = ""
    @Published var networkAddress = ""
    @Published var error: String?
    @Published var benchmark = ""
    @Published var benchmarking = false
    @Published var comparing = false
    @Published var telemetryRate = TelemetryRate()
    @Published var telemetryHistory: [TelemetryPoint] = []
    @Published var batteryLevel: Float = -1
    @Published var batteryCharging = false
    @Published var clearingCache = false
    @Published var cacheBytes: UInt64 = 0
    private var previousTelemetry: RuntimeTelemetry?
    @Published var benchmarkRecords: [BenchmarkRecord] = []
    private var comparisonTask: Task<Void, Never>?
    private var benchmarkTask: Task<Void, Never>?
    private var savedAPIKey: String?
    private var userStoppedComparison = false
    private var restartAfterStop = false
    private let runtime = lp_runtime_create()
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let documents = URL.documentsDirectory.appending(path: "Models", directoryHint: .isDirectory)
    var deviceProfile: DeviceProfile { DeviceProfile(snapshot: snapshot) }
    var selectedModel: ModelFile? { models.first { $0.url.path == configuration.modelPath } }
    var canEdit: Bool { !snapshot.isActive && !importing && !comparing && !clearingCache }
    var canStart: Bool { !importing && !comparing && !clearingCache && (configuration.mode == .node || selectedModel?.header != nil) }
    var connectionHost: String? { configuration.connection == .usb ? "127.0.0.1" : NetworkHost.normalized(networkAddress) }
    var connectionCommand: String? { connectionHost.map { configuration.macCommand(address: $0) } }
    var statusTitle: String {
        switch snapshot.state {
        case "running": "Online"
        case "starting": configuration.mode == .server ? "Loading model" : "Starting node"
        case "stopping": "Stopping"
        case "failed": "Needs attention"
        default: "Standby"
        }
    }
    private var benchmarkFile: URL { URL.documentsDirectory.appending(path: "Benchmarks.json") }
    private let smokeMode = ProcessInfo.processInfo.arguments.contains("--llamapad-smoke-node") ? "node"
        : ProcessInfo.processInfo.arguments.contains("--llamapad-smoke-server") ? "server" : nil
    private let rpcNodeOnLaunch = ProcessInfo.processInfo.arguments.contains("--llamapad-rpc-node")

    init() {
        if let data = UserDefaults.standard.data(forKey: "configuration"),
           let saved = try? JSONDecoder().decode(RuntimeConfiguration.self, from: data) {
            configuration = saved
        }
        // Secrets are stored separately from the editable configuration.
        savedAPIKey = KeyStore.read()
        configuration.apiKey = savedAPIKey ?? UUID().uuidString + UUID().uuidString
        networkAddress = UserDefaults.standard.string(forKey: "network-address") ?? Self.localAddress() ?? ""
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        var modelDirectory = documents
        var backupValues = URLResourceValues()
        backupValues.isExcludedFromBackup = true
        try? modelDirectory.setResourceValues(backupValues)
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshCacheSize()
        refreshModels()
        poll()
        if UserDefaults.standard.data(forKey: "configuration") == nil {
            configuration.apply(.balanced, device: deviceProfile)
        }
        if let data = try? Data(contentsOf: benchmarkFile),
           let saved = try? JSONDecoder().decode([BenchmarkRecord].self, from: data) {
            benchmarkRecords = saved
        }
    }

    func refreshModels() {
        models = ((try? FileManager.default.contentsOfDirectory(at: documents,
            includingPropertiesForKeys: [.fileSizeKey])) ?? [])
            .filter { $0.pathExtension.lowercased() == "gguf" }
            .map { ModelFile(url: $0) }.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        // The container path may change after reinstalling the app.
        let previousName = URL(fileURLWithPath: configuration.modelPath).lastPathComponent
        configuration.modelPath = (models.first { $0.fileName == previousName } ?? models.first { $0.header != nil })?.url.path ?? ""
    }

    func selectModel(_ file: ModelFile) {
        guard canEdit, file.header != nil else { return }
        changeMode(.server)
        let previousAlias = selectedModel?.suggestedAlias
        configuration.modelPath = file.url.path
        if configuration.modelAlias == "llamapad" || configuration.modelAlias == previousAlias {
            configuration.modelAlias = file.suggestedAlias
        }
    }

    func removeModel(_ file: ModelFile) {
        guard canEdit else { return }
        do {
            try FileManager.default.removeItem(at: file.url)
            refreshModels()
        } catch { self.error = "Could not remove the model: \(error.localizedDescription)" }
    }

    func changeMode(_ mode: ServiceMode) {
        guard canEdit, configuration.mode != mode else { return }
        saveSettings()
        let outgoing = configuration
        var next = RuntimeConfiguration()
        next.apply(.balanced, device: deviceProfile)
        if let data = UserDefaults.standard.data(forKey: "configuration-" + mode.rawValue),
           let saved = try? JSONDecoder().decode(RuntimeConfiguration.self, from: data) { next = saved }
        else {
            next.connection = outgoing.connection
            next.modelPath = outgoing.modelPath
            next.modelAlias = outgoing.modelAlias
            next.port = mode.port
        }
        next.mode = mode
        next.apiKey = outgoing.apiKey
        configuration = next
        refreshModels()
        telemetryHistory = []
        previousTelemetry = nil
    }

    func saveSettings() {
#if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("--llamapad-monitor-fixture") else { return }
#endif
        guard smokeMode == nil, !rpcNodeOnLaunch, !comparing else { return }
        do { try persist(configuration) }
        catch { self.error = error.localizedDescription }
    }

    private func persist(_ config: RuntimeConfiguration) throws {
        if savedAPIKey != config.apiKey {
            try KeyStore.save(config.apiKey)
            savedAPIKey = config.apiKey
        }
        var saved = config
        saved.apiKey = ""
        let data = try JSONEncoder().encode(saved)
        UserDefaults.standard.set(data, forKey: "configuration")
        UserDefaults.standard.set(data, forKey: "configuration-" + config.mode.rawValue)
    }

    func saveNetworkAddress() {
        UserDefaults.standard.set(networkAddress, forKey: "network-address")
    }

    func detectNetworkAddress() {
        if let address = Self.localAddress() { networkAddress = address }
        else { error = "No local network address is available. Connect the iPad to Wi-Fi and try again." }
    }

    private static func localAddress() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }
        var found: [(String, String)] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = current {
            let item = pointer.pointee
            if let addr = item.ifa_addr, Int32(addr.pointee.sa_family) == AF_INET,
               item.ifa_flags & UInt32(IFF_UP) != 0, item.ifa_flags & UInt32(IFF_LOOPBACK) == 0 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                    found.append((String(cString: item.ifa_name), String(decoding: bytes, as: UTF8.self)))
                }
            }
            current = item.ifa_next
        }
        return (found.first { $0.0 == "en0" } ?? found.first { $0.0.hasPrefix("en") })?.1
    }

    var diagnosticReport: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0.2.0"
        let report = """
        LlamaPad \(version) · \(Date().formatted())
        State: \(snapshot.state) · \(snapshot.message)
        Mode: \(configuration.mode.title) · \(configuration.connection.title)
        GPU: \(snapshot.gpuName) · family \(snapshot.gpuFamily)
        Runtime: \(snapshot.revision)
        Available app allocation: \(snapshot.availableMemory) bytes
        \(configuration.mode == .node ? "RPC buffers" : "App footprint"): \(snapshot.allocatedMemory) bytes
        Thermal state: \(snapshot.thermalState) · Low Power Mode: \(snapshot.lowPowerMode)
        Context: \(configuration.contextSize) · Batch: \(configuration.batchSize) · Micro batch: \(configuration.microBatchSize)
        Model: \(selectedModel?.fileName ?? "None on this iPad")

        \(snapshot.logs.suffix(100).joined(separator: "\n"))
        """
        return configuration.apiKey.isEmpty ? report : report.replacingOccurrences(of: configuration.apiKey, with: "[redacted]")
    }

    func importModel(_ source: URL) async {
        guard canEdit else { return }
        changeMode(.server)
        importing = true
        importingName = source.lastPathComponent
        defer { importing = false; importingName = "" }
        do {
            guard source.pathExtension.lowercased() == "gguf" else { throw ConfigurationError("Select a .gguf model.") }
            var destination = documents.appending(path: source.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                destination = documents.appending(path: source.deletingPathExtension().lastPathComponent + "-" + UUID().uuidString.prefix(8) + ".gguf")
            }
            let target = destination
            try await Task.detached(priority: .userInitiated) {
                let access = source.startAccessingSecurityScopedResource()
                defer { if access { source.stopAccessingSecurityScopedResource() } }
                _ = try GGUFHeader(url: source)
                let sourceBytes = Int64((try source.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
                let available = try target.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
                if let available, sourceBytes > available {
                    throw ConfigurationError("There isn't enough storage to import this model. Free at least \(ByteCountFormatter.string(fromByteCount: sourceBytes - available, countStyle: .file)) and try again.")
                }
                // Copy to a temporary filename so interrupted copies cannot be selected as models.
                let temporary = target.appendingPathExtension("importing")
                defer { try? FileManager.default.removeItem(at: temporary) }
                try FileManager.default.copyItem(at: source, to: temporary)
                try FileManager.default.moveItem(at: temporary, to: target)
                var noBackup = URLResourceValues()
                noBackup.isExcludedFromBackup = true
                var file = target
                try file.setResourceValues(noBackup)
            }.value
            let previousAlias = selectedModel?.suggestedAlias
            refreshModels()
            configuration.modelPath = target.path
            if configuration.modelAlias == "llamapad" || configuration.modelAlias == previousAlias,
               let file = selectedModel { configuration.modelAlias = file.suggestedAlias }
        } catch { self.error = error.localizedDescription }
    }

    @discardableResult
    func start(persist: Bool = true) -> Bool {
        do {
            configuration.cacheDirectory = URL.cachesDirectory.appending(path: "RPC", directoryHint: .isDirectory).path
            let config = try configuration.validated()
            if persist, smokeMode == nil, !rpcNodeOnLaunch {
                try self.persist(config)
            }
            let text = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
            if let failure = lp_runtime_start(runtime, text) {
                defer { lp_string_free(failure) }
                throw ConfigurationError(String(cString: failure))
            }
            poll()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func restart() {
        guard configuration.mode == .node, snapshot.state == "running" else { return }
        stop()
        restartAfterStop = true
    }

    func stop() {
        restartAfterStop = false
        userStoppedComparison = true
        comparisonTask?.cancel()
        benchmarkTask?.cancel()
        lp_runtime_stop(runtime)
        poll()
    }

    func applyPreset(_ preset: PerformancePreset) {
        poll()
        configuration.apply(preset, device: deviceProfile)
    }

    func observeRuntime() async {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--llamapad-monitor-fixture") {
            loadMonitorFixture()
            return
        }
#endif
        // A tethered Mac can start a real-model worker without editing saved settings.
        if rpcNodeOnLaunch, !snapshot.isActive {
            configuration = RuntimeConfiguration()
            configuration.apply(.balanced, device: deviceProfile)
            configuration.mode = .node
            configuration.port = ServiceMode.node.port
            if let text = ProcessInfo.processInfo.environment["LLAMAPAD_RPC_MEMORY_MIB"] {
                guard let budget = Int(text), (512...12288).contains(budget) else {
                    error = "RPC launch memory budget must be 512–12,288 MiB."
                    return
                }
                configuration.nodeMemoryMiB = budget
            }
            start(persist: false)
        }
        // Explicit launch arguments allow real-device integration tests via
        // devicectl without changing the user's saved settings.
        if let mode = smokeMode, !snapshot.isActive {
            configuration = RuntimeConfiguration()
            configuration.apply(.balanced, device: deviceProfile)
            configuration.mode = mode == "node" ? .node : .server
            configuration.port = configuration.mode.port
            configuration.nodeMemoryMiB = 512
            configuration.contextSize = 512
            configuration.apiKey = "llamapad-local-smoke-test"
            configuration.modelPath = documents.appending(path: "stories15M-q4_0.gguf").path
            start(persist: false)
        }
        while !Task.isCancelled {
            poll()
            if smokeMode != nil, let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: URL.documentsDirectory.appending(path: "SmokeStatus.json"), options: .atomic)
            }
            if rpcNodeOnLaunch, let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: URL.documentsDirectory.appending(path: "RuntimeStatus.json"), options: .atomic)
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func poll() {
        guard let text = lp_runtime_snapshot(runtime) else { return }
        defer { lp_string_free(text) }
        do {
            snapshot = try JSONDecoder().decode(RuntimeSnapshot.self, from: Data(String(cString: text).utf8))
            if let telemetry = snapshot.telemetry {
                if let previousTelemetry, telemetry.uptime < previousTelemetry.uptime {
                    telemetryHistory.removeAll(keepingCapacity: true)
                }
                telemetryRate = TelemetryRate(previous: previousTelemetry, current: telemetry)
                if snapshot.isActive {
                    telemetryHistory.append(TelemetryPoint(time: telemetry.timestamp, rate: telemetryRate, thermalState: snapshot.thermalState))
                    telemetryHistory.removeAll { $0.time < telemetry.timestamp - 60 }
                }
                previousTelemetry = telemetry
            }
            batteryLevel = UIDevice.current.batteryLevel
            batteryCharging = [.charging, .full].contains(UIDevice.current.batteryState)
        }
        catch { self.error = "Could not read service status: \(error.localizedDescription)" }
        if restartAfterStop, snapshot.state == "stopped" {
            restartAfterStop = false
            start()
        }
        UIApplication.shared.isIdleTimerDisabled = snapshot.isActive
        if !snapshot.isActive, backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

#if DEBUG
    private func loadMonitorFixture() {
        configuration = RuntimeConfiguration()
        configuration.mode = .node
        configuration.port = ServiceMode.node.port
        snapshot.state = "running"
        snapshot.message = "Monitoring layout test data"
        snapshot.thermalState = 1
        snapshot.gpuName = "Apple GPU (UI test fixture)"
        let fields: [String: Any] = ["timestamp": 100, "cpuSeconds": 10, "cpuCores": 8,
            "appMemory": 4_000_000_000, "uptime": 100, "bytesReceived": 4_300_000_000,
            "bytesSent": 150_000_000, "graphCalls": 900, "dispatchMilliseconds": 1800,
            "connectedClients": 1, "allocationLimit": 10_737_418_240, "gpuCommands": 2700,
            "gpuMilliseconds": 22000]
        if let data = try? JSONSerialization.data(withJSONObject: fields) {
            snapshot.telemetry = try? JSONDecoder().decode(RuntimeTelemetry.self, from: data)
        }
        telemetryHistory = (0...160).map { index in
            var rate = TelemetryRate()
            rate.cpuFraction = 0.18 + 0.12 * sin(Double(index) / 9)
            rate.gpuMilliseconds = 8 + 4 * sin(Double(index) / 7)
            rate.receiveBytesPerSecond = 32_768 + 16_384 * sin(Double(index) / 8)
            rate.sendBytesPerSecond = 640 + 320 * sin(Double(index) / 6)
            rate.graphsPerSecond = 30 + 5 * sin(Double(index) / 12)
            return TelemetryPoint(time: Double(index) * 0.625, rate: rate, thermalState: index < 90 ? 0 : index < 130 ? 2 : 1)
        }
        telemetryRate.cpuFraction = 0.185
        telemetryRate.gpuMilliseconds = 8.2
        telemetryRate.receiveBytesPerSecond = 32_768
        telemetryRate.sendBytesPerSecond = 640
        telemetryRate.graphsPerSecond = 30
        telemetryRate.dispatchMilliseconds = 2
    }
#endif

    func refreshCacheSize() {
        let cache = URL.cachesDirectory.appending(path: "RPC", directoryHint: .isDirectory)
        cacheBytes = ((try? FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
            .reduce(0) { $0 + UInt64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    func clearRPCCache() {
        guard canEdit, !clearingCache else { return }
        clearingCache = true
        Task {
            do {
                try await Task.detached(priority: .utility) {
                    let cache = URL.cachesDirectory.appending(path: "RPC", directoryHint: .isDirectory)
                    if FileManager.default.fileExists(atPath: cache.path) { try FileManager.default.removeItem(at: cache) }
                }.value
                refreshCacheSize()
            } catch { self.error = "Could not clear the RPC cache: \(error.localizedDescription)" }
            clearingCache = false
        }
    }

    func enterBackground() {
        guard snapshot.isActive else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Stop llama") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.stop()
                if self.backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(self.backgroundTask)
                    self.backgroundTask = .invalid
                }
            }
        }
        stop()
    }

    func runBenchmark() {
        guard !benchmarking, !comparing, snapshot.state == "running", configuration.mode == .server else { return }
        benchmarking = true
        benchmarkTask = Task {
            defer { benchmarking = false; benchmarkTask = nil }
            do {
                let record = try await measure(configuration)
                save(record)
                benchmark = String(format: "Prompt %.1f · Generation %.1f tokens/s · Median of 3 runs",
                    record.promptTokensPerSecond, record.generationTokensPerSecond)
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    private func measure(_ config: RuntimeConfiguration) async throws -> BenchmarkRecord {
        var prompts: [Double] = [], generations: [Double] = []
        for run in 0..<4 {
            try Task.checkCancellation()
            guard snapshot.state == "running" else { throw ConfigurationError("The service stopped during measurement.") }
            guard snapshot.thermalState < 2 else { throw ConfigurationError("Let the iPad cool before continuing the comparison.") }
            let url = URL(string: "http://127.0.0.1:\(config.port)/completion")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 180
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "prompt": String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 32),
                "n_predict": 128, "temperature": 0, "seed": 42, "cache_prompt": false, "ignore_eos": true
            ])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ConfigurationError(String(decoding: data, as: UTF8.self)) }
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let timings = object?["timings"] as? [String: Any],
                  let prompt = timings["prompt_per_second"] as? Double,
                  let generation = timings["predicted_per_second"] as? Double else { throw ConfigurationError("No timing data returned.") }
            // The first request warms the kernels and is excluded from results.
            if run > 0 { prompts.append(prompt); generations.append(generation) }
        }
        return BenchmarkRecord(configuration: config, snapshot: snapshot, prompt: prompts, generation: generations)
    }

    private func save(_ record: BenchmarkRecord) {
        benchmarkRecords.append(record)
        benchmarkRecords = Array(benchmarkRecords.suffix(40))
        if let data = try? JSONEncoder().encode(benchmarkRecords) { try? data.write(to: benchmarkFile, options: .atomic) }
    }

    func compareBatchSizes() {
        guard !comparing, !benchmarking, configuration.mode == .server, snapshot.state == "running" else { return }
        comparing = true; benchmarking = true; userStoppedComparison = false
        let original = configuration
        let upper = min(original.batchSize, max(original.microBatchSize, deviceProfile.throughputMicroBatch))
        let candidates = Array(Set([64, 128, 256, 512, original.microBatchSize].filter { $0 <= upper })).sorted()
        comparisonTask = Task {
            defer {
                configuration = original
                comparing = false; benchmarking = false; comparisonTask = nil
            }
            do {
                var results: [BenchmarkRecord] = []
                for size in candidates {
                    try Task.checkCancellation()
                    lp_runtime_stop(runtime)
                    try await waitForState("stopped")
                    configuration = original
                    configuration.microBatchSize = size
                    benchmark = "Measuring micro batch \(size)…"
                    guard start(persist: false) else { throw ConfigurationError(error ?? "Could not restart the service.") }
                    try await waitForState("running")
                    let result = try await measure(configuration)
                    save(result)
                    results.append(result)
                }
                lp_runtime_stop(runtime)
                try await waitForState("stopped")
                if let fastest = results.max(by: { $0.promptTokensPerSecond < $1.promptTokensPerSecond }) {
                    benchmark = "Comparison complete. Best prompt rate: micro batch \(fastest.microBatch). Review the measurements below; original settings restored."
                }
            } catch {
                lp_runtime_stop(runtime)
                if !userStoppedComparison { self.error = error.localizedDescription }
            }
        }
    }

    private func waitForState(_ state: String) async throws {
        for _ in 0..<1200 {
            try Task.checkCancellation()
            poll()
            if snapshot.state == state { return }
            if snapshot.state == "failed" { throw ConfigurationError(snapshot.message) }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ConfigurationError("Timed out waiting for the service to become \(state).")
    }

    func useBenchmark(_ record: BenchmarkRecord) {
        guard canEdit, record.model == selectedModel?.fileName else { return }
        configuration.microBatchSize = min(record.microBatch, configuration.batchSize)
    }
}

private enum KeyStore {
    static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "LlamaPad", kSecAttrAccount as String: "server-api-key"] }
    static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
    static func save(_ key: String) throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw ConfigurationError("Could not update the API key in Keychain (\(status)).") }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw ConfigurationError("Could not save the API key in Keychain (\(added)).") }
    }
}
