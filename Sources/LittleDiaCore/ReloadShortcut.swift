/// ⌘R and ⌘⇧R, which Dia ignores in its popups: the app reloads the focused little window's page instead.
public enum ReloadShortcut {
    /// The modifier keys that matter for the shortcut (Caps Lock and Fn don't).
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    /// For a key press: nil if it isn't the shortcut, false for ⌘R, true for ⌘⇧R (reload without the cache).
    /// `characters` are the key's characters ignoring modifiers, so other keyboard layouts match by letter, as the
    /// browser's own ⌘R does. Holding the keys down reloads once.
    public static func bypassCache(characters: String?, modifiers: Modifiers, isRepeat: Bool) -> Bool? {
        guard !isRepeat, characters?.lowercased() == "r", modifiers.contains(.command),
              modifiers.isDisjoint(with: [.option, .control]) else { return nil }
        return modifiers.contains(.shift)
    }
}
