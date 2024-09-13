//
//  ProgressBar+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

#if os(macOS)
import SwiftUI

extension ProgressBar {
    var content: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                base
                loadingBar(for: geometry.size.width)
            }
            .padding(.horizontal, 25)
        }
    }
    
    func loadingBar(for width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 30)
            .frame(width: width*progress-50, height: 10)
            .foregroundStyle(LinearGradient.progressGradient)
            .animation(.easeInOut, value: progress)
    }
}
#endif
