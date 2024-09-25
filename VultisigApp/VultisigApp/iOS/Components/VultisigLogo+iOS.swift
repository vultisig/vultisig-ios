//
//  VultisigLogo+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

#if os(iOS)
import SwiftUI

extension VultisigLogo {
    var container: some View {
        content
    }
    
    var descriptionContainer: some View {
        descriptionContent
            .padding(.top, 10)
    }
}
#endif
