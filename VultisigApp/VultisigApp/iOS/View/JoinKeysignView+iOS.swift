//
//  JoinKeysignView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension JoinKeysignView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationTitle(NSLocalizedString("joinKeySign", comment: "Join Keysign"))
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