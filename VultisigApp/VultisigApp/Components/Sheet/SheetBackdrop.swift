//
//  SheetBackdrop.swift
//  VultisigApp
//

/// What a `crossPlatformSheet` does to the app behind it while it is up.
enum SheetBackdrop {
    /// Blurs and dims it.
    case blurred
    /// Dims it and keeps it sharp, for a sheet that should read as part of the
    /// screen it sits over.
    case dimOnly
}
