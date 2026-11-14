package com.rohit.lan_mouse_mobile

/// Shared live state for client-mode input, written by the platform
/// channel (desktop events arriving via Dart) and read by the
/// injection services.
object ClientInputState {
    /// xkb-style modifier masks from the desktop's KeyboardModifiers
    /// events. Bit numbering follows the xkb modifier map:
    /// 0x01 shift, 0x02 lock (caps), 0x04 control, 0x08 alt (Mod1),
    /// 0x40 super (Mod4).
    @Volatile
    var modifiersDepressed: Int = 0

    @Volatile
    var modifiersLocked: Int = 0
}
