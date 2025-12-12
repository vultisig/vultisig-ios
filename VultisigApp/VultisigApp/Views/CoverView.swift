//
//  CoverView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-17.
//

import SwiftUI

struct CoverView: View {
    var body: some View {
        VultisigLogo()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PrimaryBackgroundWithGradient())
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

#Preview {
    CoverView()
}
