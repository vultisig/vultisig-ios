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
        content
            .textInputAutocapitalization(.never)
    }

    func pasteAddress() {
        if let clipboardContent = UIPasteboard.general.string {
            memo = clipboardContent
        }
    }
}
#endif
