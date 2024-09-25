//
//  PeerCell+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(macOS)
import SwiftUI

extension PeerCell {
    var content: some View {
        ZStack(alignment: .topTrailing) {
            cell
            check
        }
        .scaleEffect(0.7)
        .clipped()
        .frame(width: 110, height: 140)
    }
    
    func setData() {
        isPhone = false
    }
}
#endif
