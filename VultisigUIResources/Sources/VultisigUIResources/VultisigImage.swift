import SwiftUI

/// A named image from the shared app and widget resource catalog.
public struct VultisigImage: View {
    public let image: Image

    public init(_ name: String) {
        image = Image(name, bundle: VultisigResources.bundle)
    }

    public var body: some View {
        image
    }

    public func resizable(capInsets: EdgeInsets = EdgeInsets(),
                          resizingMode: Image.ResizingMode = .stretch) -> Image {
        image.resizable(capInsets: capInsets, resizingMode: resizingMode)
    }
}
