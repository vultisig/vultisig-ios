//
//  TransactionMemoDetailsView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension TransactionMemoDetailsView {
    var content: some View {
        ZStack {
            Background()
            view
        }
        .gesture(DragGesture())
    }
    
    var view: some View {
        VStack {
            fields
            button
        }
        .padding(.horizontal, 25)
    }
}
#endif
