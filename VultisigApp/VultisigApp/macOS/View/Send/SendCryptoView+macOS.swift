//
//  SendCryptoView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(macOS)
import SwiftUI

extension SendCryptoView {
    var container: some View {
        content
    }
    
    var main: some View {
        VStack {
            headerMac
            view
        }
    }
    
    var headerMac: some View {
        SendCryptoHeader(
            tx: tx,
            vault: vault, 
            showFeeSettings: tx.coin.supportsFeeSettings,
            settingsPresented: $settingsPresented,
            sendCryptoViewModel: sendCryptoViewModel,
            shareSheetViewModel: shareSheetViewModel
        )
    }
}
#endif
