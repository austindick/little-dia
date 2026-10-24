import Foundation
import Testing
@testable import LittleDiaCore

private let b = Bounds(left: 300, top: 137, width: 1000, height: 750)

@Test func encodesOpenExactly() throws {
    let data = try MessageCoding.encode(OutboundMessage.open(requestId: "r1", url: URL(string: "https://github.com/")!, bounds: b, focused: true))
    #expect(String(decoding: data, as: UTF8.self) == #"{"bounds":{"height":750,"left":300,"top":137,"width":1000},"focused":true,"requestId":"r1","type":"open","url":"https://github.com/"}"#)
}

@Test func encodesMoveExactly() throws {
    #expect(String(decoding: try MessageCoding.encode(OutboundMessage.move(windowId: 42)), as: UTF8.self) == #"{"type":"move","windowId":42}"#)
}

@Test func encodesCloseExactly() throws {
    #expect(String(decoding: try MessageCoding.encode(OutboundMessage.close(windowId: 42)), as: UTF8.self) == #"{"type":"close","windowId":42}"#)
}

@Test func decodesOpenedWithoutRequestId() throws {
    let json = #"{"type":"opened","windowId":42,"url":"https://github.com/pulls","bounds":{"left":300,"top":137,"width":1000,"height":750}}"#
    #expect(try MessageCoding.decodeInbound(Data(json.utf8)) == .opened(requestId: nil, windowId: 42, url: "https://github.com/pulls", bounds: b))
}

@Test func keepsURLsExactlyAsTheBrowserSentThem() throws {   // review #10: Copy must not re-encode | [ ] or %zz
    let raw = "https://grafana.example.com/d/x?var-env=a|b&filter[status]=open&q=%zz"
    let json = #"{"type":"littleURL","windowId":7,"url":"\#(raw)"}"#
    #expect(try MessageCoding.decodeInbound(Data(json.utf8)) == .littleURL(windowId: 7, url: raw))
}

@Test func decodesLittleMoved() throws {
    #expect(try MessageCoding.decodeInbound(Data(#"{"type":"littleMoved","windowId":42}"#.utf8)) == .littleMoved(windowId: 42))
}

@Test func decodesExtensionLog() throws {
    #expect(try MessageCoding.decodeInbound(Data(#"{"type":"log","message":"move: kept page"}"#.utf8)) == .log(message: "move: kept page"))
}

@Test func rejectsUnknownType() {
    #expect(throws: (any Error).self) { try MessageCoding.decodeInbound(Data(#"{"type":"bogus"}"#.utf8)) }
}

@Test func realWorldURLSurvivesRoundTrip() throws {   // Review Focus 3
    let s = "https://docs.google.com/document/d/1AbC_xyz/edit?usp=sharing&q=caf%C3%A9%20au%20lait#heading=h.2x"
    let m = InboundMessage.littleURL(windowId: 7, url: s)
    #expect(try MessageCoding.decodeInbound(try MessageCoding.encode(m)) == m)
}

@Test func hostHelloRoundTrips() throws {
    let m = InboundMessage.hostHello(browserBundleID: "company.thebrowser.dia", browserPID: 1234)
    #expect(try MessageCoding.decodeInbound(try MessageCoding.encode(m)) == m)
}

@Test func rejectsCopyMessage() {   // the extension never sends it; Copy reads the URL the app already tracks
    #expect(throws: (any Error).self) { try MessageCoding.decodeInbound(Data(#"{"type":"copy","url":"https://a.b/"}"#.utf8)) }
}
