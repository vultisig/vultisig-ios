//
//  LinearSeparator.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-24.
//

import SwiftUI

struct LinearSeparator: View {
    var body: some View {
        Rectangle()
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .foregroundStyle(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Color(red: 0.02, green: 0.11, blue: 0.23), location: 0.00),
                        Gradient.Stop(color: Color(red: 0.16, green: 0.27, blue: 0.44), location: 0.49),
                        Gradient.Stop(color: Color(red: 0.02, green: 0.11, blue: 0.23), location: 1.00)
                    ],
                    startPoint: UnitPoint(x: 0, y: 0.5),
                    endPoint: UnitPoint(x: 1, y: 0.5)
                )
            )
            .opacity(0.8)
    }
}

#Preview {
    LinearSeparator()
}
