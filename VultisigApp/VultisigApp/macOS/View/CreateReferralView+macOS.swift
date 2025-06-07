//
//  CreateReferralView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-07.
//

#if os(macOS)
import SwiftUI

extension CreateReferralView {
    var container: some View {
        VStack(spacing: 0) {
            header
            content
        }
    }
    
    var header: some View {
        GeneralMacHeader(title: "createReferral")
    }
}
#endif
