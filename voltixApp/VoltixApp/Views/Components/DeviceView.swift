import SwiftUI

struct DeviceView: View {
    let number: String
    let description: String
    let deviceImg: String
    let deviceDescription: String

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .center, spacing: 16) {
                Text(number)
                    .font(.system(size: geometry.size.width < 600 ? 40 : 80, weight: .light))
                    .lineSpacing(geometry.size.width < 600 ? 60 : 120)
                
                Text(description)
                    .font(.system(size: geometry.size.width < 600 ? 13 : 24, weight: .medium))
                    .lineSpacing(geometry.size.width < 600 ? 19.5 : 36)
                
                Image(deviceImg)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometry.size.width < 600 ? 148.29 : 304, height: geometry.size.width < 600 ? 148.29 : 304)
                
                Text(deviceDescription)
                    .font(.system(size: geometry.size.width < 600 ? 13 : 24, weight: .medium))
                    .lineSpacing(geometry.size.width < 600 ? 19.5 : 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(geometry.size.width < 600 ? 16 : 32)
        }
        .background(Color.clear) // Explicitly clear to ensure it adapts to system background color
    }
}

// Preview
struct DeviceView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceView(
            number: "1",
            description: "MAIN",
            deviceImg: "Device3", // Ensure this image is added to your Xcode project's asset catalog
            deviceDescription: "A MACBOOK"
        )
        .previewLayout(.sizeThatFits)
    }
}
