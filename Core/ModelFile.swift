import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A quick format check before copying a potentially multi-gigabyte file.
/// Full tensor validation remains the runtime's responsibility.
public struct GGUFHeader: Equatable, Sendable {
    public let version: UInt32
    public let tensorCount: UInt64
    public let metadataCount: UInt64

    public init(data: Data) throws {
        let bytes = Array(data.prefix(24))
        guard bytes.count == 24, Array(bytes.prefix(4)) == Array("GGUF".utf8) else {
            throw ConfigurationError("This file does not contain a valid GGUF header.")
        }
        func integer(_ start: Int, _ count: Int) -> UInt64 {
            bytes[start..<(start + count)].enumerated().reduce(0) { $0 | UInt64($1.element) << ($1.offset * 8) }
        }
        let version = UInt32(integer(4, 4))
        guard version == 2 || version == 3 else {
            throw ConfigurationError("GGUF version \(version) is not supported. Choose a version 2 or 3 model.")
        }
        let tensors = integer(8, 8)
        let metadata = integer(16, 8)
        guard tensors > 0, metadata > 0 else {
            throw ConfigurationError("This GGUF has no model tensors or metadata.")
        }
        self.version = version
        tensorCount = tensors
        metadataCount = metadata
    }

    public init(url: URL) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        try self.init(data: file.read(upToCount: 24) ?? Data())
    }
}

public struct ModelFile: Identifiable, Sendable {
    public let url: URL
    public let byteCount: Int64
    public let header: GGUFHeader?
    public var id: String { url.path }
    public var name: String { url.deletingPathExtension().lastPathComponent }
    public var fileName: String { url.lastPathComponent }
    public var sizeDescription: String { ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file) }
    public var suggestedAlias: String {
        String(name.lowercased().map { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) ? $0 : "-" }.prefix(100))
    }
    public init(url: URL) {
        self.url = url
        byteCount = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        header = try? GGUFHeader(url: url)
    }
}

public enum NetworkHost {
    /// Accept hostnames and IP literals while excluding URL paths and shell syntax.
    public static func normalized(_ input: String) -> String? {
        var host = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        guard !host.isEmpty, host.count <= 253 else { return nil }
        if host.contains(":") {
            var address = in6_addr()
            return host.withCString { inet_pton(AF_INET6, $0, &address) } == 1 ? host : nil
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" &&
            label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }) else { return nil }
        if labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
            guard labels.count == 4, labels.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }) else { return nil }
        }
        return host
    }
    public static func authority(_ host: String) -> String { host.contains(":") ? "[\(host)]" : host }
}
