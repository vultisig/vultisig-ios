import SwiftUI

struct DeviceView: View {
    let number: String
    let description: String
    let deviceImg: String
    let deviceDescription: String
    
    var body: some View {
        
        VStack(alignment: .center) {
            HStack{
                VStack{
                    // Replace Button with Image and increase its size
                    Image(systemName: number)
                        .resizable() // Makes the image resizable
                        .scaledToFit() // Scales the image to fit its container
                        .frame(width: 50, height: 50) // Specify your desired size
                    Text(description).font(.system(size: 15, weight: .light))
                }
                VStack{
                    // Replace Button with Image and increase its size
                    Image(systemName: deviceImg)
                        .symbolRenderingMode(.monochrome)
                        .resizable() // Makes the image resizable
                        .scaledToFit() // Scales the image to fit its container
                        .frame(width: 200, height: 100) // Specify your desired size
                    Text(deviceDescription)
                }
            }.padding()
        }
    }
}


// Preview
struct DeviceView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceView(
            number: "1.circle",
            description: "MAIN",
            deviceImg: "macbook", // Ensure this image is added to your Xcode project's asset catalog
            deviceDescription: "A MACBOOK"
        )
        .previewLayout(.sizeThatFits)
        DeviceView(
            number: "2.circle",
            description: "MAIN",
            deviceImg: "macbook.and.iphone", // Ensure this image is added to your Xcode project's asset catalog
            deviceDescription: "A MACBOOK"
        )
        .previewLayout(.sizeThatFits)
        DeviceView(
            number: "3.circle",
            description: "MAIN",
            deviceImg: "macbook.and.ipad", // Ensure this image is added to your Xcode project's asset catalog
            deviceDescription: "A MACBOOK"
        )
        .previewLayout(.sizeThatFits)
    }
}
