
import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    var qrCodeImage: UIImage
    var body: some View {
        Image(uiImage: qrCodeImage)
            .resizable()
            .scaledToFit().frame(width: 250, height: 250)
    }
}
