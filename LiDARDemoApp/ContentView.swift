//
//  ContentView.swift
//  LiDARDemoApp
//
//  Created by megumi terada on 2021/08/21.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    
    let captureWithDepth = AVCaptureWithDepth()

    @Environment(\.imageScale) var imageScale
    @State var image: UIImage? = nil
    @State var isAvCaptureRunning: Bool = false
    @State var scanDeviceName: String = ""
        
    var body: some View {
        VStack {
            
            // Capture Screen
            VStack (alignment: .center) {
                
                Spacer()
                
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .frame(maxWidth: 600, maxHeight: 800)
                        .scaledToFit()
                        //.background(sizeReader())
                }
                
                Text(scanDeviceName)
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()
            }
            .frame(maxWidth: 600, maxHeight: 900)
            .background(Color.black)
            
            
            // Capture Button
            Button(action: {
                
                if (isAvCaptureRunning) {
                    isAvCaptureRunning.toggle()
                    captureWithDepth.runAR { uiImage in
                        DispatchQueue.main.async {
                            self.image = uiImage
                        }
                    }
                    self.scanDeviceName = "LiDAR"
                } else {
                    isAvCaptureRunning.toggle()
                    captureWithDepth.runAvCapture { uiImage in
                        DispatchQueue.main.async {
                            self.image = uiImage
                        }
                    }
                    self.scanDeviceName = "Normal"
                }
                
            }) {
                Circle()
                    .frame(width: 60, height: 60, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
            }
            .frame(width: 80, height: 80, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
            .background(Color.white)
            .cornerRadius(40.0)
            .padding()
            .padding(.bottom)
            
        }
        .background(Color.black)
        .edgesIgnoringSafeArea(/*@START_MENU_TOKEN@*/.all/*@END_MENU_TOKEN@*/)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
