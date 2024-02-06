//
//  RadioButtonGroup.swift
//  VoltixApp
//
//  Created by Mac on 05.02.2024.
//

import SwiftUI

struct ColorInvert: ViewModifier {

    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        Group {
            if colorScheme == .dark {
                content.colorInvert()
            } else {
                content
            }
        }
    }
}

struct RadioButton: View {

    @Environment(\.colorScheme) var colorScheme

    let id: String
    let callback: (String)->()
    let selectedID : String
    let size: CGFloat
    let color: Color
    let textSize: CGFloat

    init(
        _ id: String,
        callback: @escaping (String)->(),
        selectedID: String,
        size: CGFloat = 20,
        color: Color = Color.primary,
        textSize: CGFloat = 14
        ) {
        self.id = id
        self.size = size
        self.color = color
        self.textSize = textSize
        self.selectedID = selectedID
        self.callback = callback
    }

    var body: some View {
        Button(action:{
            self.callback(self.id)
        }) {
            HStack() {
                Spacer()
                Text(id)
                    .font(Font.system(size: textSize))
                Spacer().frame(width: 16)
                Image(systemName: self.selectedID == self.id ? "largecircle.fill.circle" : "circle")
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: self.size, height: self.size)
                    .modifier(ColorInvert())
                
            }
            .foregroundColor(self.color)
            .padding(.trailing, 30)
        }
        .foregroundColor(self.color)
    }
}

struct RadioButtonGroup: View {

    let items : [String]

    @State var selectedId: String = ""

    let callback: (String) -> ()

    var body: some View {
        VStack {
            ForEach(items.indices, id: \.self) { index in
                RadioButton(items[index], callback: radioGroupCallback, selectedID: selectedId)
            }
        }
    }

    func radioGroupCallback(id: String) {
        selectedId = id
        callback(id)
    }
}

#Preview {
    RadioButtonGroup(
        items: [
            "I’VE SAVED A BACKUP OF THE VAULT",
            "NOBODY BUT ME CAN ACCESS THE BACKUP",
            "IT’S NOT LOCATED WITH THE OTHER BACKUP",
        ],
        selectedId: "I’VE SAVED A BACKUP OF THE VAULT"
    ) {
        selected in print("Selected is: \(selected)")
    }
}
