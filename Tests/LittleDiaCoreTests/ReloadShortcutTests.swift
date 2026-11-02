import Testing
@testable import LittleDiaCore

@Test func commandRReloads() {
    #expect(ReloadShortcut.bypassCache(characters: "r", modifiers: [.command], isRepeat: false) == false)
}

@Test func commandShiftRReloadsWithoutTheCache() {
    // With Shift held, the key's characters ignoring modifiers can still come through as an upper-case R.
    #expect(ReloadShortcut.bypassCache(characters: "R", modifiers: [.command, .shift], isRepeat: false) == true)
    #expect(ReloadShortcut.bypassCache(characters: "r", modifiers: [.command, .shift], isRepeat: false) == true)
}

@Test func otherKeysAndModifiersAreNotReload() {
    #expect(ReloadShortcut.bypassCache(characters: "r", modifiers: [], isRepeat: false) == nil)
    #expect(ReloadShortcut.bypassCache(characters: "t", modifiers: [.command], isRepeat: false) == nil)
    #expect(ReloadShortcut.bypassCache(characters: "r", modifiers: [.command, .option], isRepeat: false) == nil)
    #expect(ReloadShortcut.bypassCache(characters: "r", modifiers: [.command, .control], isRepeat: false) == nil)
    #expect(ReloadShortcut.bypassCache(characters: nil, modifiers: [.command], isRepeat: false) == nil)
}

@Test func holdingTheKeysDownReloadsOnce() {
    #expect(ReloadShortcut.bypassCache(characters: "r", modifiers: [.command], isRepeat: true) == nil)
}
