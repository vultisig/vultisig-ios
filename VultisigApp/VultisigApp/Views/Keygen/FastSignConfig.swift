//
//  FastSignConfig.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 01.11.2024.
//

import Foundation

struct FastSignConfig: Hashable {
    let email: String
    let password: String
    let hint: String?
    let isExist: Bool
}
