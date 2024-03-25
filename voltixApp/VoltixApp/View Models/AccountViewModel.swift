//
//  AccountViewModel.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-24.
//

import SwiftUI

@MainActor
class AccountViewModel: ObservableObject {
    @AppStorage("showOnboarding") var showOnboarding: Bool = true
}
