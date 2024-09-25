//
//  PeerCell+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(iOS)
import SwiftUI

extension PeerCell {
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var content: some View {
        ZStack(alignment: .topTrailing) {
            cell
            check
        }
        .scaleEffect(isPhone ? 0.7 : 1)
        .clipped()
        .frame(
            width: isPhone ? 100 : 150,
            height: isPhone ? 140 : 200
        )
    }
    
    func setData() {
        isPhone = idiom == .phone
    }
}
#endif
