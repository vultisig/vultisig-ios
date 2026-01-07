//
//  Icon.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

import SwiftUI

struct Icon: View {
    let name: String
    let color: Color?
    let size: CGFloat
    let isSystem: Bool
    
    init(named: String, color: Color? = Theme.colors.primaryAccent4, size: CGFloat = 20, isSystem: Bool = false) {
        self.name = named
        self.color = color
        self.size = size
        self.isSystem = isSystem
    }
    
    var body: some View {
        if isSystem {
            Image(systemName: name)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundColor(color)
        } else {
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundColor(color)
        }
    }
}
