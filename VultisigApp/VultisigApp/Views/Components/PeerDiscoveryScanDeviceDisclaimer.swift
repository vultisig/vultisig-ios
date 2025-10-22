//
//  PeerDiscoveryScanDeviceDisclaimer.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-27.
//

import SwiftUI

struct PeerDiscoveryScanDeviceDisclaimer: View {
    @Binding var showAlert: Bool
    
    var body: some View {
        InfoBannerView(
            description: "peerDiscoveryScanDeviceDisclaimer".localized,
            type: .info,
            leadingIcon: "circle-info"
        ) {
            showAlert = false
        }
    }
}

#Preview {
    PeerDiscoveryScanDeviceDisclaimer(showAlert: .constant(false))
}
