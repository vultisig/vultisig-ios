//
//  AuthenticationType.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

import Foundation

enum AuthenticationType: String {
    case None = "retry"
    case TouchID = "loginUsingTouchID"
    case FaceID = "loginUsingFaceID"
    case OpticID = "loginUsingOpticID"
}
