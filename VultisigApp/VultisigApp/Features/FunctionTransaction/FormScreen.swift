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
    /// Hard-disables the Continue button regardless of `validForm`. Used by
    /// flows with a pre-flight that no field edit can satisfy (e.g. liquid
    /// balance below the network fee), so the button reads as disabled rather
    /// than silently no-op'ing. Defaults to `false` to preserve the existing
    /// "tap Continue to open the validator/address picker" affordance, where
    /// the button must stay tappable while the form is still incomplete.
    let isContinueDisabled: Bool
    var onContinue: () -> Void
    var content: () -> Content

    @State var scrollViewProxy: ScrollViewProxy?

    init(
        title: String,
        fixedHeight: Bool = true,
        validForm: Binding<Bool>,
        isContinueDisabled: Bool = false,
        onContinue: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.fixedHeight = fixedHeight
        self._validForm = validForm
        self.isContinueDisabled = isContinueDisabled
        self.onContinue = onContinue
        self.content = content
    }

    var body: some View {
        Screen {
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
                .disabled(isContinueDisabled)
            }
        }
        .screenTitle(title)
    }
}
