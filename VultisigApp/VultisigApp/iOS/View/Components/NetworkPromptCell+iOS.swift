//
//  NetworkPromptCell+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

#if os(iOS)
import SwiftUI

extension NetworkPromptCell {
    var content: some View {
        ZStack {
            if UIDevice.current.userInterfaceIdiom == .phone {
                phoneCell
            } else {
                padCell
            }
        }
    }
}
#endif
