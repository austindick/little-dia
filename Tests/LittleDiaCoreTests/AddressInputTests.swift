import Foundation
import Testing
@testable import LittleDiaCore

@Test func webAddressesOpenAsTyped() {
    #expect(AddressInput.url(from: "https://github.com/pulls") == URL(string: "https://github.com/pulls"))
    #expect(AddressInput.url(from: "  http://example.com  ") == URL(string: "http://example.com"))
}

@Test func addressesWithoutASchemeGetHTTPS() {
    #expect(AddressInput.url(from: "example.com") == URL(string: "https://example.com"))
    #expect(AddressInput.url(from: "docs.google.com/document/d/1") == URL(string: "https://docs.google.com/document/d/1"))
    #expect(AddressInput.url(from: "localhost:8080/app") == URL(string: "https://localhost:8080/app"))
    #expect(AddressInput.url(from: "localhost") == URL(string: "https://localhost"))
}

@Test func anythingElseIsAGoogleSearch() {
    #expect(AddressInput.url(from: "swift testing") == URL(string: "https://www.google.com/search?q=swift%20testing"))
    #expect(AddressInput.url(from: "dia") == URL(string: "https://www.google.com/search?q=dia"))
    #expect(AddressInput.url(from: "a&b=c?") == URL(string: "https://www.google.com/search?q=a%26b%3Dc%3F"))
    // A trailing dot isn't an address.
    #expect(AddressInput.url(from: "e.g.") == URL(string: "https://www.google.com/search?q=e.g."))
}

@Test func otherSchemesAreSearchedNotOpened() {
    for text in ["javascript:alert(1)", "file:///etc/hosts", "chrome://extensions"] {
        #expect(AddressInput.url(from: text)?.host == "www.google.com", "\(text)")
    }
}

@Test func emptyTextIsNothing() {
    #expect(AddressInput.url(from: "") == nil)
    #expect(AddressInput.url(from: "   \n") == nil)
}
