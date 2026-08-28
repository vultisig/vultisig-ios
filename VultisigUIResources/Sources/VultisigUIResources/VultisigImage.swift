import SwiftUI

public enum VultisigImage: String, CaseIterable, Sendable {
    case binanceSmartChain = "bsc"
    case bitcoin = "btc"
    case ethereum = "eth"
    case logoOutline = "logo-outline"
    case solana
    case tether = "usdt"

    public var resource: ImageResource {
        ImageResource(name: rawValue, bundle: VultisigResources.bundle)
    }

    public var image: Image {
        Image(resource)
    }
}
