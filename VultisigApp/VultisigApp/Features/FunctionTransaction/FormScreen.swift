//
//  FormScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

struct FormScreen<Content: View>: View {
    let title: String
    let fixedHeight: Bool
    @Binding var validForm: Bool
    var onContinue: () -> Void
    var content: () -> Content

    @State var scrollViewProxy: ScrollViewProxy?

    init(
        title: String,
        fixedHeight: Bool = true,
        validForm: Binding<Bool>,
        onContinue: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.fixedHeight = fixedHeight
        self._validForm = validForm
        self.onContinue = onContinue
        self.content = content
    }

    var body: some View {
        Screen(title: title) {
            VStack(spacing: 12) {
                GeometryReader { geo in
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 12) {
                                content()
                            }
                            .frame(height: fixedHeight ? geo.size.height : nil, alignment: .top)
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
