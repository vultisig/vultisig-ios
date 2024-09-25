//
//  MemoTextField+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

#if os(iOS)
import SwiftUI

extension MemoTextField {
    var container: some View {
        HStack(spacing: 0) {
            textField
                .textInputAutocapitalization(.never)
        }
    }
}
#endif
