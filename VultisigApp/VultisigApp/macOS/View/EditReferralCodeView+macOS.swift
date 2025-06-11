//
//  EditReferralCodeView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-06.
//

#if os(macOS)
import SwiftUI

extension EditReferredCodeView {
    var container: some View {
        VStack(spacing: 0) {
            header
            content
        }
    }
    
    var header: some View {
        GeneralMacHeader(title: "editReferredCode")
    }
}
#endif
