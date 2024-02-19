//
//  DeviceView.swift
//  VoltixApp
//
//  Created by Mac on 05.02.2024.
//

import SwiftUI

struct DeviceView: View {
    let number: String;
    let description: String;
    let deviceImg: String;
    let deviceDescription: String;
    
    var body: some View {
        #if os(iOS)
            smallScreen(
                number: number,
                description: description,
                deviceImg: deviceImg,
                deviceDescription: deviceDescription
            )
        #else
            largeScreen(
                number: number,
                description: description,
                deviceImg: deviceImg,
                deviceDescription: deviceDescription
            )
        #endif
    }
}


private struct smallScreen: View {
    let number: String;
    let description: String;
    let deviceImg: String;
    let deviceDescription: String;
    var body: some View {
        ZStack() {
          HStack(spacing: 0) {
            Rectangle()
              .foregroundColor(.clear)
              .frame(width: 148.29, height: 148.29)
              .background(
                Image(deviceImg)
              )
          }
          .frame(width: 148.29, height: 148.29)
          .offset(x: 14.65, y: -35.35)
          Text(deviceDescription)
            .font(Font.custom("Montserrat", size: 13).weight(.medium))
            .lineSpacing(19.50)
            
            .offset(x: 14.50, y: 28.50)
          Text(description)
            .font(Font.custom("Montserrat", size: 13).weight(.medium))
            .lineSpacing(19.50)
            
            .offset(x: -119, y: -5.50)
          ZStack() {
            Text(number)
              .font(Font.custom("Montserrat", size: 40).weight(.light))
              .lineSpacing(60)
              
              .offset(x: 0, y: 0)
            Ellipse()
              .foregroundColor(.clear)
              .frame(width: 50, height: 50)
              .overlay(Ellipse()
              .inset(by: 1)
              .stroke(.black, lineWidth: 1))
              .offset(x: 0, y: 0)
          }
          .frame(width: 50, height: 50)
          .offset(x: -119.50, y: -50.50)
        }
        .frame(width: 271, height: 150);
    }
}

private struct largeScreen: View {
    let number: String;
    let description: String;
    let deviceImg: String;
    let deviceDescription: String;
    var body: some View {
        VStack() {
            ZStack() {
              Text(number)
                .font(Font.custom("Montserrat", size: 80).weight(.light))
                .lineSpacing(120)
                
              Ellipse()
                .foregroundColor(.clear)
                .frame(width: 100, height: 100)
                .overlay(Ellipse()
                .inset(by: 1)
                .stroke(.black, lineWidth: 1))
            }
            .frame(width: 100, height: 100)
            Text(description)
                .font(Font.custom("Montserrat", size: 24).weight(.medium))
                .lineSpacing(30)
                
                .padding(.top, 8)
            Image(deviceImg)
                .resizable()
                .frame(width: 304, height: 304)
            Text(deviceDescription)
                .font(Font.custom("Montserrat", size: 24).weight(.medium))
                .lineSpacing(30)
                
        }
    }
}

#Preview {
    DeviceView(
        number: "1",
        description: "MAIN",
        deviceImg: "Device3",
        deviceDescription: "A MACBOOK"
    )
}
