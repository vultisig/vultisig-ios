//
//  BlowfishViewModel.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 02/08/24.
//

import Foundation
import Combine
import SwiftUI

@MainActor
class BlowfishWarningViewModel: ObservableObject {
    @Published var blowfishResponse: [String] = []
    
    var hasWarnings: Bool {
        return !blowfishResponse.isEmpty
    }
    
    var warningMessages: [String] {
        return blowfishResponse
    }
    
    var backgroundColor: Color {
        hasWarnings ? Color.warningYellow.opacity(0.35) : Color.green.opacity(0.35)
    }
    
    var borderColor: Color {
        hasWarnings ? Color.warningYellow : Color.green
    }
    
    var iconName: String {
        hasWarnings ? "exclamationmark.triangle" : "checkmark.shield"
    }
    
    var iconColor: Color {
        hasWarnings ? Color.warningYellow : Color.green
    }
    
    func updateResponse(_ response: [String]) {
        blowfishResponse = response
    }
}
