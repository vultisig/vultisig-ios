
import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    var qrCodeImage: Image
    var body: some View {
        qrCodeImage
            .resizable()
            .scaledToFit()
    }
}
