//
//  SendViewModel.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 10.04.2024.
//

import Foundation

@MainActor protocol TransferViewModel: AnyObject {
    var hash: String? { get set }
    var approveHash: String? { get set }
    func moveToNextView()
}

class FakeTransferViewModel: ObservableObject, TransferViewModel {
    var hash: String?
    
    var approveHash: String?

    init() { }

    func moveToNextView() {

    }
}
