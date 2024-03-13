//
//  WebSVGImage.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import SwiftUI
import SDWebImageSwiftUI

struct WebSVGImage: View {
    let url: String
    var size: CGFloat = 48
    
    var body: some View {
        WebImage(url: URL(string: url)) { image in
            image
                .resizable()
                .frame(width: size, height: size)
        } placeholder: {
            progressView
        }
    }
    
    var progressView: some View {
        ProgressView()
            .tint(.black)
            .frame(width: size, height: size)
            .background(Color.neutral200)
            .cornerRadius(size*2)
    }
}

#Preview {
    WebSVGImage(url: "https://static2.finnhub.io/file/publicdatany/finnhubimage/stock_logo/IBM.svg")
}
