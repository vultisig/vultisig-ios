//
//  SendDetailsScreen+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(macOS)
import SwiftUI

extension SendDetailsScreen {
    var container: some View {
        ZStack(alignment: .center) {
            Screen(title: "send".localized) {
                content
            }
            
            overlay
                .showIf(sendDetailsViewModel.showCoinPickerSheet || sendDetailsViewModel.showChainPickerSheet)
            chainPicker
                .showIf(sendDetailsViewModel.showChainPickerSheet)
            coinPicker
                .showIf(sendDetailsViewModel.showCoinPickerSheet)
        }
    }
    
    var view: some View {
        VStack {
            tabs
            buttonContainer
                .padding(.horizontal, 8)
                .padding(.vertical, -12)
        }
    }
    
    var buttonContainer: some View {
        button
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
    }
    
    func setData() {
        Task {
            await getBalance()
        }
    }
    
    var overlay: some View {
        MacOSOverlay()
            .onTapGesture(perform: closeSheets)
    }
    
    func closeSheets() {
        sendDetailsViewModel.showCoinPickerSheet = false
        sendDetailsViewModel.showChainPickerSheet = false
    }
}
#endif
