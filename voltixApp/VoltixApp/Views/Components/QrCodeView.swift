
import SwiftUI


#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    
#if os(iOS)
    var qrCodeImage: UIImage
#elseif os(macOS)
    var qrCodeImage: NSImage
#endif
    
    var body: some View {
#if os(iOS)
        Image(uiImage: qrCodeImage)
            .resizable()
            .scaledToFit().frame(width: 250, height: 250)
#elseif os(macOS)
        Image(nsImage: qrCodeImage)
            .resizable()
            .scaledToFit().frame(width: 250, height: 250)
#endif
    }
}

