//
//  ReferralSendOverviewView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-11.
//

#if os(macOS)
import SwiftUI

extension ReferralSendOverviewView {
    var container: some View {
        VStack(spacing: 0) {
            header
            content
        }
    }
    
    var header: some View {
        GeneralMacHeader(title: "sendOverview")
    }
}
#endif
