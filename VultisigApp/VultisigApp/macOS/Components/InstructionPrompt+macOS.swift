//
//  InstructionPrompt+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

#if os(macOS)
import SwiftUI

extension InstructionPrompt {
    var content: some View {
        padContent
            .frame(maxWidth: .infinity)
            .frame(maxWidth: 350)
    }
}
#endif
