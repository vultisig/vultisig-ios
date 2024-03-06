//
//  SwapDoneView.swift
//  VoltixApp
//

import SwiftUI

struct SwapDoneView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                Text("Transaction")
                    .font(.body20MenloBold)
                    .lineSpacing(30)
                    
                HStack() {
                    Text("bc1psrjtwm7682v6nhx2uwfgcfelrennd7pcvqq7v6w")
                        .font(.body13MontserratMedium)
                        .lineSpacing(19.50)
                        
                    Spacer()
                    Image("Link")
                        .resizable()
                        .frame(width: 23, height: 30)
                }
                .padding(.trailing, 16)
            }
            .padding(.leading, 20)
            .frame(height: 83)
            Spacer()
            BottomBar(
                content: "COMPLETE",
                onClick: { }
            )
        }
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: 0,
            maxHeight: .infinity,
            alignment: .top
        )
    }
}

#Preview {
    SwapDoneView(presentationStack: .constant([]))
}
