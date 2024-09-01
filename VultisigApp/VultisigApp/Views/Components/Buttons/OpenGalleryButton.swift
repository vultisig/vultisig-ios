//
//  OpenGalleryButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-15.
//

#if os(iOS)
import SwiftUI

struct OpenButton: View {
    @State var buttonIcon: String
    @State var buttonLabel: String
    
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var body: some View {
        content
            .frame(width: 180, height: 54)
            .background(Color.turquoise600)
            .cornerRadius(100)
    }
    
    var content: some View {
        HStack(spacing: 6) {
            Image(systemName: buttonIcon)
                .font(idiom == .phone ? .body12Menlo : .body16MontserratBold)
                .foregroundColor(.blue600)
            
            Text(NSLocalizedString(buttonLabel, comment: ""))
                .font(idiom == .phone ? .body12MontserratBold : .body16MontserratBold)
                .foregroundColor(.blue600)
        }
    }
}

#Preview {
    HStack {
        OpenButton(buttonIcon: "photo.stack", buttonLabel: "uploadFromGallery")
        OpenButton(buttonIcon: "folder", buttonLabel: "uploadFromFiles")
    }
    .padding(.horizontal, 12)
}
#endif
