//
//  SendViewModel.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 10.04.2024.
//

import Foundation

@MainActor protocol TransferViewModel: AnyObject {
    var hash: String? { get set }
    func moveToNextView()
}
