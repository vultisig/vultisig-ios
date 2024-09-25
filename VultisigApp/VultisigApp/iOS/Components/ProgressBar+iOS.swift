//
//  ProgressBar+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

#if os(iOS)
import SwiftUI

extension ProgressBar {
    var content: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                base
                loadingBar(for: geometry.size.width)
            }
        }
    }
    
    func loadingBar(for width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 30)
            .frame(width: width*progress, height: 10)
            .foregroundStyle(LinearGradient.progressGradient)
            .animation(.easeInOut, value: progress)
    }
}
#endif
