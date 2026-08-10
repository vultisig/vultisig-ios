//
//  UIApplicationExtension.swift
//  VultisigApp
//

#if os(iOS)
import UIKit

extension UIApplication {

    /// Every scene the user is actually in front of. More than one on iPad and
    /// on the Mac, where the app's `WindowGroup` and `DocumentGroup` can both be
    /// open at once.
    var activeWindowScenes: [UIWindowScene] {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
    }

    /// The window the app's own content is in: a key window at the normal level,
    /// in a scene that is in the foreground.
    ///
    /// `windows.first` is not this. The array is unordered, so it hands back
    /// whichever window the app happens to own first — a window the app raised
    /// over its content included.
    ///
    /// The level filter is the part that matters most: a window raised *above*
    /// the content is raised precisely so that nothing can be drawn over it, and
    /// presenting a UIKit alert into it would undo that. While such a window is
    /// key this answers `nil`, which is the right failure — nothing presented
    /// beats something presented over the lock screen.
    var activeContentWindow: UIWindow? {
        activeWindowScenes
            .flatMap(\.windows)
            .first { $0.isKeyWindow && $0.windowLevel == .normal }
    }
}
#endif
