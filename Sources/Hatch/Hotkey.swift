import Carbon.HIToolbox

/// Global hotkey via Carbon, which needs no Accessibility permission.
final class HotKey {
    private static var callback: (() -> Void)?
    private static var handlerInstalled = false
    private var ref: EventHotKeyRef?

    /// Nil when the system refuses the combination (usually because another app owns it).
    init?(keyCode: Int, modifiers: Int, onPress: @escaping () -> Void) {
        Self.callback = onPress
        if !Self.handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                HotKey.callback?()
                return noErr
            }, 1, &spec, nil, nil)
            Self.handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x48544348), id: 1)
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
    }

    deinit { if let ref { UnregisterEventHotKey(ref) } }
}
