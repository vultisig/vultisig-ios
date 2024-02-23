import SwiftUI

struct MenuItem: View {
    let content: String
    let onClick: () -> Void
    
    var body: some View {
        Button(action: onClick) {
            HStack {
                Spacer()
                Text(content)
                    .font(Font.custom("Menlo", size: 35).weight(.bold))
                    .lineSpacing(60)
                
                Spacer().frame(width: 20)
                Image(systemName: "chevron.right")
                    .resizable()
                    .frame(width: 18, height: 27)
            }
            .padding()
            .frame(height: 70)
        }
    }
}

    // Correct PreviewProvider Implementation
struct MenuItem_Previews: PreviewProvider {
    static var previews: some View {
        MenuItem(
            content: "VAULT RECOVERY",
            onClick: { }
        )
    }
}
