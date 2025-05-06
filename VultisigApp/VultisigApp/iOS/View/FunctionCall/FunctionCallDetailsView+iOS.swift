//
//  FunctionCallDetailsView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(iOS)
import SwiftUI

extension FunctionCallDetailsView {
    var content: some View {
        ZStack {
            Background()
            view
        }
        .gesture(DragGesture())
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    hideKeyboard()
                } label: {
                    Text(NSLocalizedString("done", comment: "Done"))
                }
            }
        }
    }
    
    var view: some View {
        VStack {
            fields
            button
        }
    }
    
    var fields: some View {
        ScrollView {
            VStack(spacing: 16) {
                contractSelector
                functionSelector
                fnCallInstance.view
            }
            .padding(.horizontal, 16)
            .padding(.bottom, keyboardObserver.keyboardHeight)
        }
    }
}
#endif
