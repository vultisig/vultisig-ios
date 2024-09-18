//
//  InstructionPrompt+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

#if os(iOS)
import SwiftUI

extension InstructionPrompt {
    var content: some View {
        ZStack {
            if UIDevice.current.userInterfaceIdiom == .phone {
                phoneContent
            } else {
                padContent
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxWidth: 350)
    }
}
#endif
