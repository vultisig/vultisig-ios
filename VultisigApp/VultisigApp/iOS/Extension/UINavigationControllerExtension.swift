//
//  UINavigationControllerExtension.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-22.
//

#if os(iOS)
import UIKit

extension UINavigationController {
    open override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        navigationBar.topItem?.backButtonDisplayMode = .minimal
    }
}
#endif
