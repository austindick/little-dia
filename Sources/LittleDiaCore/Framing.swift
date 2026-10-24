import Foundation

/// Chrome native messaging framing: a 32-bit little-endian length followed by that many bytes of UTF-8 JSON.
/// The same framing is used on the app <-> helper Unix socket so the helper can relay frames verbatim.
public enum NativeMessageFraming {
    /// Chrome's limit for messages from a native host to the extension.
    public static let maxFrameSize = 1_048_576

    public static func encode(_ payload: Data) -> Data {
        var length = UInt32(payload.count).littleEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(payload)
        return frame
    }
}

public enum FramingError: Error, Equatable {
    case frameTooLarge(Int)
}

/// Accumulates bytes from a stream and returns every complete frame's payload.
public struct FrameDecoder {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)
        var payloads: [Data] = []
        while buffer.count >= 4 {
            let header = buffer.prefix(4)
            let length = Int(header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
            if length > NativeMessageFraming.maxFrameSize {
                buffer.removeAll()
                throw FramingError.frameTooLarge(length)
            }
            guard buffer.count >= 4 + length else { break }
            let start = buffer.startIndex + 4
            payloads.append(Data(buffer[start..<start + length]))
            buffer = Data(buffer[(start + length)...])
        }
        return payloads
    }
}
