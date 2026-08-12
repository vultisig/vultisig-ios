//
//  FormScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

/// Shared form chrome: a scrolling body and a Continue button beneath it.
///
/// **Continue is deliberately not gated on the form's validity**, and it used to
/// take a `validForm` binding that said otherwise — one this screen never read.
/// The binding is gone because it described an enforcement that does not exist
/// here and, twice, was relied on as though it did.
///
/// The reason it cannot exist is that Continue is not a submit button on most of
/// these screens. It advances focus from the address field to the amount field
/// (Bond, Bond/Unbond Maya), it opens the validator or pool picker when nothing
/// is selected yet (Cosmos redelegate, staking, TON stake), and everywhere it
/// calls a `transactionBuilder` that begins with `validateErrors()` — the tap is
/// what reveals the field errors on a form the user has not touched. Disabling
/// it on `!validForm` would take all three away and leave a greyed-out button
/// with nothing explaining itself.
///
/// Validity is enforced where the transaction is built, not where the button is
/// drawn: every caller's `transactionBuilder` guards on its own `validForm` and
/// returns `nil`, so an invalid form navigates nowhere. `isContinueDisabled` is
/// for the other case — a pre-flight condition NO field edit can satisfy, where
/// a tappable button would be a lie in the opposite direction.
struct FormScreen<Content: View>: View {
    let title: String
    let fixedHeight: Bool
    /// Hard-disables the Continue button. For flows with a pre-flight that no
    /// field edit can satisfy — a liquid balance below the network fee, a
    /// position that cannot be withdrawn at all — so the button reads as
    /// disabled rather than silently no-op'ing. Defaults to `false`, which is
    /// the tap-to-advance/tap-to-reveal behaviour described above.
    let isContinueDisabled: Bool
    var onContinue: () -> Void
    var content: () -> Content

    @State var scrollViewProxy: ScrollViewProxy?

    init(
        title: String,
        fixedHeight: Bool = true,
        isContinueDisabled: Bool = false,
        onContinue: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.fixedHeight = fixedHeight
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
