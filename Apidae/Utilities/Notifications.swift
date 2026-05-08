import Foundation

/// All notification names in one place.
extension Notification.Name {
    static let apidaeLock = Notification.Name("apidaeLock")
    static let apidaeUnlock = Notification.Name("apidaeUnlock")
    static let apidaeUnlockPassword = Notification.Name("apidaeUnlockPassword")
    static let apidaeInputBlockerFailed = Notification.Name("apidaeInputBlockerFailed")
    static let apidaeSessionLost = Notification.Name("apidaeSessionLost")
    static let toggleApidae = Notification.Name("toggleApidae")
    static let apidaeHotkeyPreferenceChanged = Notification.Name("apidaeHotkeyPreferenceChanged")
}
