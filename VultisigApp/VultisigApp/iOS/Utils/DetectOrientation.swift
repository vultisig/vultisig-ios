//
//  DetectOrientation.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-24.
//

#if os(iOS)
import SwiftUI

struct DetectOrientation: ViewModifier {
    @Binding var orientation: UIDeviceOrientation

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                orientation = UIDevice.current.orientation
            }
    }
}
#endif
