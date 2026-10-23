import Foundation
import Testing
@testable import LilBrowCore

@Test func encodePrefixesLittleEndianLength() {
    #expect(NativeMessageFraming.encode(Data("{}".utf8)) == Data([2, 0, 0, 0, 0x7B, 0x7D]))
}

@Test func decodesFrameSplitAcrossChunks() throws {
    var d = FrameDecoder()
    let frame = NativeMessageFraming.encode(Data("{\"a\":1}".utf8))
    #expect(try d.append(frame.prefix(3)).isEmpty)
    #expect(try d.append(frame.dropFirst(3)) == [Data("{\"a\":1}".utf8)])
}

@Test func decodesTwoFramesInOneChunk() throws {
    var d = FrameDecoder()
    let chunk = NativeMessageFraming.encode(Data("1".utf8)) + NativeMessageFraming.encode(Data("22".utf8))
    #expect(try d.append(chunk) == [Data("1".utf8), Data("22".utf8)])
}

@Test func rejectsOversizeFrame() {
    var d = FrameDecoder()
    var n = UInt32(2_000_000).littleEndian
    let header = Data(bytes: &n, count: 4)
    #expect(throws: FramingError.frameTooLarge(2_000_000)) { try d.append(header) }
}
