//
//  JoinKeygenView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension JoinKeygenView {
    var content: some View {
        ZStack {
            Background()
            shadow
            main
        }
    }
    
    var main: some View {
        VStack(spacing: .zero) {
            headerMac
                .showIf(viewModel.status != .KeygenStarted)
            Spacer()
            states
            Spacer()
        }
    }
    
    var headerMac: some View {
        JoinKeygenHeader(title: "joinKeygen", hideBackButton: hideBackButton)
    }
}
#endif
