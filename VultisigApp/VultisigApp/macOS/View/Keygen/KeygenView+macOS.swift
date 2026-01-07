//
//  KeygenView+imacOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension KeygenView {
    var content: some View {
        container
            .onLoad {
                Task{
                    await setData()
                    await viewModel.startKeygen(context: context)
                }
            }
    }
}
#endif
