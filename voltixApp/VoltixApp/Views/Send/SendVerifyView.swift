import SwiftUI

struct SendVerifyView: View {
  @Binding var presentationStack: [CurrentScreen]

  var body: some View {
    NavigationStack {
      GeometryReader { geometry in  // Use GeometryReader for dynamic sizing
        // Allows content to be scrollable
        VStack(alignment: .leading) {
          Group {
            VStack(alignment: .leading) {
              Text("FROM")
                .font(.system(size: geometry.size.width * 0.05, weight: .bold))  // Dynamic font sizing
                .foregroundColor(.black)
              Text("0x0cb1D4a24292bB89862f599Ac5B10F42b6DE07e4")
                .font(.system(size: geometry.size.width * 0.04))  // Dynamic font sizing
                .foregroundColor(.black)
            }
            VStack(alignment: .leading) {
              Text("TO")
                .font(.system(size: geometry.size.width * 0.05, weight: .bold))  // Dynamic font sizing
                .foregroundColor(.black)
              Text("0xF42b6DE07e40cb1D4a24292bB89862f599Ac5B10")
                .font(.system(size: geometry.size.width * 0.04))  // Dynamic font sizing
                .foregroundColor(.black)
            }
            HStack {
              Text("AMOUNT")
                .font(.system(size: geometry.size.width * 0.05, weight: .bold))  // Dynamic font sizing
                .foregroundColor(.black)
              Spacer().frame(width: geometry.size.width * 0.1)  // Dynamic spacing
              Text("1.0 ETH")
                .font(.system(size: geometry.size.width * 0.08, weight: .light))  // Dynamic font sizing
                .foregroundColor(.black)
            }
            VStack(alignment: .leading) {
              Text("MEMO")
                .font(.system(size: geometry.size.width * 0.05, weight: .bold))  // Dynamic font sizing
                .foregroundColor(.black)
              Text("TEST")
                .font(.system(size: geometry.size.width * 0.04))  // Dynamic font sizing
                .foregroundColor(.black)
            }
            HStack {
              Text("GAS")
                .font(.system(size: geometry.size.width * 0.05, weight: .bold))  // Dynamic font sizing
                .foregroundColor(.black)
              Spacer().frame(width: geometry.size.width * 0.1)  // Dynamic spacing
              Text("$4.00")
                .font(.system(size: geometry.size.width * 0.08, weight: .light))  // Dynamic font sizing
                .foregroundColor(.black)
            }
          }
          .frame(height: geometry.size.height * 0.1)  // Dynamic height for each block
          Spacer()
          Group {

            RadioButtonGroup(
              items: [
                "I am sending to the right address",
                "The amount is correct",
                "I am not being hacked or phished",
              ],
              selectedId: "iPhone 15 Pro, “Matt’s iPhone”, 42"
            ) { selected in
              print("Selected is: \(selected)")
            }
            .padding(.horizontal, geometry.size.width * 0.03)  // Dynamic padding
            BottomBar(
              content: "COMPLETE",
              onClick: {}
            )
            .padding(.horizontal, geometry.size.width * 0.03)  // Dynamic padding
          }

        }
        .padding(.leading, geometry.size.width * 0.05)  // Dynamic leading padding
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
      //.edgesIgnoringSafeArea(.all) // Extend to the edges of the display
    }
  }
}

// Preview
struct SendVerifyView_Previews: PreviewProvider {
  static var previews: some View {
    SendVerifyView(presentationStack: .constant([]))
  }
}
