import Foundation

public enum VultisigResources {
    public static var bundle: Bundle {
        .module
    }

    public static func registerFonts() {
        FontRegistrar.shared.registerAll()
    }
}
