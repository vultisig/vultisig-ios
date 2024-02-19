//
//  FileItem.swift
//  VoltixApp
//
//  Created by dev on 09.02.2024.
//

import SwiftUI

struct FileItem: View {
    let icon: String;
    let filename: String;
    
    var body: some View {
        VStack {
           HStack {
               Image(self.icon)
             .resizable()
             .frame(width: 30, height: 30)
             
             Spacer().frame(width: 8)
               Text(self.filename)
                .font(Font.custom("Montserrat", size: 24).weight(.medium))
                .lineSpacing(36)
                ;
           }
           .padding()
        }
        .padding(.top, 16)
    }
}

#Preview {
    FileItem(
        icon: "MinusCircle",
        filename: "123.txt"
    )
}
