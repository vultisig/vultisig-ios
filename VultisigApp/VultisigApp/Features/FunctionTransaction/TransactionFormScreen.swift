//
//  TransactionFormScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

struct TransactionFormScreen<Content: View>: View {
    let title: String
    @Binding var validForm: Bool
    var onContinue: () -> Void
    var content: () -> Content
    
    @State var scrollViewProxy: ScrollViewProxy?
    
    init(title: String, validForm: Binding<Bool>, onContinue: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._validForm = validForm
        self.onContinue = onContinue
        self.content = content
    }
    
    var body: some View {
        Screen(title: title) {
            VStack(spacing: .zero) {
                GeometryReader { geo in
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 12) {
                                content()
                                Spacer()
                            }
                            .frame(height: geo.size.height)
                        }
                        .onLoad {
                            scrollViewProxy = proxy
                        }
                    }
                }
                PrimaryButton(title: "continue".localized) {
                    onContinue()
                }
            }
        }
    }
}
