import SwiftUI

struct AddressItem: View {
    let coinName: String
    let address: String

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(coinName)
                    .font(.custom("Menlo", size: 20))
                    .fontWeight(.bold)
                    .lineSpacing(30)
                    .foregroundColor(Color.primary) // Adapts to light/dark mode
                    .padding(.bottom, 5)
                
                Text(address)
                    .font(.custom("Montserrat", size: 13))
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .lineSpacing(19.5)
                    .foregroundColor(Color.secondary) // Adapts to light/dark mode
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10)
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "doc.on.clipboard") // Using a system image that adapts automatically
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(Color.blue) // Adapts well in both light and dark mode
                    .frame(width: 32, height: 30)
            }
            .frame(width: 50, height: 30)
            .buttonStyle(PlainButtonStyle())
            .offset(y: 10)
        }
        .padding(.trailing, 16)
        // No explicit background color is set, so it adapts to system background
    }
}

// Preview
struct AddressItem_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AddressItem(coinName: "Bitcoin", address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh")
        }
    }
}
