import SwiftUI

struct SendInputDetailsView: View {
  @Binding var presentationStack: [CurrentScreen]
  @State private var toAddress: String = ""
  @State private var amount: String = ""
  @State private var memo: String = ""
  @State private var gas: String = ""

  var body: some View {

    GeometryReader { geometry in
      VStack {
        VStack(alignment: .leading) {
          HStack {
            Text("Ethereum")
              .font(.system(size: geometry.size.width * 0.05, weight: .bold))
              .foregroundColor(.black)
            Spacer()
            Text("23.2")
              .font(.system(size: geometry.size.width * 0.05))
              .foregroundColor(.black)
          }
          .padding()
          .frame(height: geometry.size.height * 0.07)

          Group {
            inputField(title: "To", text: $toAddress, geometry: geometry)
            inputField(title: "Amount", text: $amount, geometry: geometry, isNumeric: true)
            inputField(title: "Memo", text: $memo, geometry: geometry)
            gasField(geometry: geometry)
          }
          .padding(.horizontal)

          Spacer()

          BottomBar(content: "CONTINUE", onClick: {})
            .padding(.horizontal)
        }
        .navigationTitle("SEND")
        .modifier(InlineNavigationBarTitleModifier())
        .toolbar {
          #if os(iOS)
            ToolbarItem(placement: .navigationBarLeading) {
              NavigationButtons.backButton(presentationStack: $presentationStack)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
              NavigationButtons.questionMarkButton
            }
          #else
            ToolbarItem {
              NavigationButtons.backButton(presentationStack: $presentationStack)
            }
            ToolbarItem {
              NavigationButtons.questionMarkButton
            }
          #endif
        }
      }
    }

  }

  private func inputField(
    title: String, text: Binding<String>, geometry: GeometryProxy, isNumeric: Bool = false
  ) -> some View {
    VStack(alignment: .leading) {
      Text(title)
        .font(.system(size: geometry.size.width * 0.05, weight: .bold))
        .foregroundColor(.black)
      TextField("", text: text)
        .padding()
        .background(Color(red: 0.92, green: 0.92, blue: 0.93))
        .cornerRadius(10)
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .stroke(Color.gray, lineWidth: 1)
        )
      //.keyboardType(isNumeric ? .decimalPad : .default)
    }
    .frame(height: geometry.size.height * 0.12)
  }

  private func gasField(geometry: GeometryProxy) -> some View {
    VStack(alignment: .leading) {
      Text("Gas")
        .font(.system(size: geometry.size.width * 0.05, weight: .bold))
        .foregroundColor(.black)
      Spacer()
      HStack {
        TextField("", text: $gas)
          .padding()
          .background(Color(red: 0.92, green: 0.92, blue: 0.93))
          .cornerRadius(10)
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(Color.gray, lineWidth: 1)
          )
        Spacer()
        Text("$4.00")
          .font(.system(size: geometry.size.width * 0.05, weight: .bold))
          .foregroundColor(.black)
      }
    }
    .frame(height: geometry.size.height * 0.12)
  }
}

// Preview
struct SendInputDetailsView_Previews: PreviewProvider {
  static var previews: some View {
    SendInputDetailsView(presentationStack: .constant([]))
  }
}
