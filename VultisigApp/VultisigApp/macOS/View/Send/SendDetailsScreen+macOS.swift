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
        Screen(title: "send".localized) {
            content
        }
    }
    
    var view: some View {
        VStack {
            tabs
            button
                .padding(.horizontal, 8)
        }
    }
    
    func setData() {
        Task {
            await getBalance()
        }
    }
}
#endif
