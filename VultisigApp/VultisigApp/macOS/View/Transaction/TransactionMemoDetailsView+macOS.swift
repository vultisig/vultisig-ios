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
    
    var fields: some View {
        ScrollView {
            VStack(spacing: 16) {
                contractSelector
                functionSelector
                txMemoInstance.view
            }
            .padding(.horizontal, 16)
        }
    }
}
#endif
