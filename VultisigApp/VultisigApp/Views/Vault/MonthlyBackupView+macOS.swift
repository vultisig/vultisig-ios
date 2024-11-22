//
//  MonthlyBackupView+macOS.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 20.11.2024.
//

#if os(macOS)
import SwiftUI

extension MonthlyBackupView {

    var body: some View {
        ZStack {
            Background()
            view
                .padding(.bottom, 30)
        }
    }

}
#endif
