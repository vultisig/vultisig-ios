//
//  JoinKeygenView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(iOS)
import SwiftUI
import CodeScanner

extension JoinKeygenView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationTitle(NSLocalizedString("joinKeygen", comment: "Join keygen/reshare"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationHelpButton()
            }
        }
    }
    
    var main: some View {
        VStack {
            Spacer()
            states
            Spacer()
        }
    }
}
#endif
