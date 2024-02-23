    //
    //  Keysign.swift
    //  VoltixApp

import Foundation
import SwiftUI


struct TestViewToLayout: View {
    
        // @Binding var presentationStack: [CurrentScreen]
    
    var body: some View {
        VStack {
            HStack {
                KeyGenStatusText(status: "CREATING TSS INSTANCE... ")
            }
        }
    }
}




struct TestViewToLayout_Previews: PreviewProvider {
    static var previews: some View {
        TestViewToLayout()
    }
}

