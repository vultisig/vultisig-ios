//
//  NavigationSettingButton.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-05-02.
//

import SwiftUI

struct NavigationSettingButton: View {
    var tint: Color = Color.neutral0
    
    var body: some View {
        Image(systemName: "gear")
            .font(.body14MenloBold)
            .foregroundColor(tint)
    }
}

#Preview {
    ZStack {
        Background()
        NavigationSettingButton()
    }
}
