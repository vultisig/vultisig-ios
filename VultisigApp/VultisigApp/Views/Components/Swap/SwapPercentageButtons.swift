//
//  SwapPercentageButtons.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-25.
//

import SwiftUI

struct SwapPercentageButtons: View {
    let show100: Bool

    var buttonOptions: [Int] {
        show100 ? [25, 50, 75, 100] : [25, 50, 75]
    }

    @State var selectedPercentage: Int? = nil

    @Binding var showAllPercentageButtons: Bool

    let onTap: (Int) -> Void

    var body: some View {
        container
    }
}
