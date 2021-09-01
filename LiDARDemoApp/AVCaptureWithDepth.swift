//
//  AVCaptureWithDepth.swift
//  LiDARDemoApp
//
//  Created by megumi terada on 2021/08/22.
//

import VideoToolbox
import AVFoundation
import ARKit

class AVCaptureWithDepth: NSObject {
    
    private let captureSession: AVCaptureSession = AVCaptureSession()
    private let arSession: ARSession = ARSession()
    private let arConfiguration: ARWorldTrackingConfiguration = ARWorldTrackingConfiguration()
    
    private var handler: ((UIImage) -> Void)?
    
    private let device: MTLDevice? = MTLCreateSystemDefaultDevice()
    private var videoDevice: AVCaptureDevice?
    
    private var depthMap: CVPixelBuffer?
    private var depthArray: [Float32]?
    
    private var isProcessing = false
    private var frameCounter = 0
    
    private var x_sum = 0
    private var y_sum = 0
    
    private var centroid_x: Int? = nil
    private var centroid_y: Int? = nil
    
    private var focus_x: Int? = nil
    private var focus_y: Int? = nil
    
    private var lidarImage_W: CGFloat? = nil
    private var lidarImage_H: CGFloat? = nil
    
    private var captureImage_W: CGFloat? = nil
    private var captureImage_H: CGFloat? = nil
    
    override init() {
        super.init()
        if (checkLidarIsEnable() && checkPermission()) {
            self.setupCaptureDevice()
            self.setupLiDAR()
        }
    }
    
    // Check whether LiDAR scanner is available
    func checkLidarIsEnable() -> Bool {
        return ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth])
    }
    
    // Check permission of camera
    func checkPermission() -> Bool {
        var isAuth = false
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: // The user has previously granted access to the camera.
                isAuth = true
            
            case .notDetermined: // The user has not yet been asked for camera access.
                
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted {
                        isAuth = true
                    }
                }
            
            case .denied: // The user has previously denied access.
                isAuth = false

            case .restricted: // The user can't grant access due to restrictions.
                isAuth = false
                
            default:
                isAuth = false
        }
        
        return isAuth
    }
    
    func setupCaptureDevice() {

        captureSession.beginConfiguration()
        videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        guard
            let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice!),
            captureSession.canAddInput(videoDeviceInput)
            else { return }
        captureSession.addInput(videoDeviceInput)
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "mdispatchqueue"))
        videoOutput.alwaysDiscardsLateVideoFrames = true

        guard captureSession.canAddOutput(videoOutput) else { return }
        captureSession.addOutput(videoOutput)

        // orientation
        for connection in videoOutput.connections {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }

        captureSession.commitConfiguration()
    }
    
    func setupLiDAR() {
        if type(of: arConfiguration).supportsFrameSemantics(.sceneDepth) {
            
            // Activate sceneDepth
            arConfiguration.isAutoFocusEnabled = false
            arConfiguration.frameSemantics = .sceneDepth
        }
        
        arSession.delegate = self
    }
    
    // TODO: You need to observe ARSession state to error handling.
    func runAR(_ handler: @escaping (UIImage) -> Void)  {
        captureSession.stopRunning()
        self.handler = handler
        arSession.run(arConfiguration)
    }
    
    func runAvCapture(_ handler: @escaping (UIImage) -> Void) {
        arSession.pause()
        self.handler = handler
        self.setMode(focusMode: .locked, exposureMode: .locked)
        captureSession.startRunning()
        
        // fPOI設定
        if let cx = centroid_x,
           let cy = centroid_y {
            // 解像度調整
            if let captureImage_W = captureImage_W,
               let captureImage_H = captureImage_H,
               let lidarImage_W = lidarImage_W,
               let lidarImage_H = lidarImage_H {
                
                let adjustPoint_x = CGFloat(cx) * (captureImage_W / lidarImage_W)
                let adjustPoint_y = CGFloat(cy) * (captureImage_H / lidarImage_H)
                
                // 正規化 (0,0) ~ (1,1)
                let x = adjustPoint_x / captureImage_W
                let y = adjustPoint_y / captureImage_H
                
                self.setMode(focusMode: .autoFocus, exposureMode: .autoExpose, point: CGPoint(x: x, y: y))
            }
        }
    }
}

// MARK: - Camera Manager
extension AVCaptureWithDepth {
    
    func setMode(focusMode: AVCaptureDevice.FocusMode,
                 exposureMode: AVCaptureDevice.ExposureMode,
                 point: CGPoint? = nil) {
        
        guard let videoDevice = videoDevice else {
            print("no videoDevice...")
            return
        }

        do {
            try videoDevice.lockForConfiguration()
        } catch {
            print("failed to lockForConfiguration...")
            return
        }
        

        if let point = point {
                        
            // ピント
            if videoDevice.isFocusPointOfInterestSupported && videoDevice.isFocusModeSupported(focusMode) {
                videoDevice.focusPointOfInterest = point
                videoDevice.focusMode = focusMode
            }

            // 露出
            if videoDevice.isExposurePointOfInterestSupported && videoDevice.isExposureModeSupported(exposureMode) {
                videoDevice.exposurePointOfInterest = point
                videoDevice.exposureMode = exposureMode
            }
            
        } else {
                        
            if (videoDevice.isFocusModeSupported(focusMode)) {
                videoDevice.focusMode = focusMode
            }
            
            if (videoDevice.isExposureModeSupported(exposureMode)) {
                videoDevice.exposureMode = exposureMode
            }
        }
        
        videoDevice.unlockForConfiguration()
    }
}

// MARK: - LiDAR function
extension AVCaptureWithDepth: ARSessionDelegate {
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        
        // preview capture
        if let handler = handler {
            guard let imageBuffer = frame.sceneDepth?.depthMap else { return }
            let ciimage = CIImage(cvPixelBuffer: imageBuffer)
            let orientation :CGImagePropertyOrientation = CGImagePropertyOrientation.right
            let orientedImage = ciimage.oriented(orientation)
            var image = self.convert(cmage: orientedImage)
            
            if (lidarImage_W == nil && lidarImage_H == nil) {
                lidarImage_W = image.size.width
                lidarImage_H = image.size.height
            }

            DispatchQueue.global(qos: .userInitiated).async {
                self.computefPOIAwait(imageBuffer: imageBuffer, image: image)
            }

            if let cx = centroid_x,
               let cy = centroid_y {

                // draw fPOI
                if let imageWithfPOI = drawRectangleOnImage(image: image, point: CGPoint(x: cx,y: cy)) {
                    image = imageWithfPOI
                }
            }
            
            handler(image)
        }
    }
    
    func computefPOIAwait(imageBuffer: CVPixelBuffer, image: UIImage) -> Void {
        let semaphore = DispatchSemaphore(value: 0)
        
        self.computefPOI(imageBuffer: imageBuffer, image: image, completion: { _ in
            semaphore.signal()
        })
        semaphore.wait()
    }
    
    func computefPOI(imageBuffer: CVPixelBuffer, image: UIImage, completion: @escaping (Int) -> Void) {
        
        // count up
        frameCounter += 1
        
        // check depth data
        buildDepthInfo(depthMap: imageBuffer)
        
        // copy cache data
        let depthArrayCache = depthArray
        
        if (frameCounter > 60) {

            // calculate average
            centroid_x = x_sum / frameCounter
            centroid_y = y_sum / frameCounter

            // clear values per 60 frames
            x_sum = 0
            y_sum = 0
            frameCounter = 0

        } else {

            // 最も手前にある物体の中心点 x, y を計算
            if let depthArrayCache = depthArrayCache,
               let minDepthVal = depthArrayCache.min(),
               let fidx = depthArrayCache.firstIndex(of: minDepthVal) {

                x_sum += (fidx % Int(image.size.width))
                y_sum += (fidx / Int(image.size.height))
            }
        }
        
        completion(0)
    }

    
    // Show error message
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard error is ARError else { return }
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        debugPrint(errorMessage)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension AVCaptureWithDepth:  AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        if let handler = handler {
            let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
            let ciimage = CIImage(cvPixelBuffer: imageBuffer)
            var image = self.convert(cmage: ciimage)
            
            if (captureImage_W == nil && captureImage_H == nil) {
                captureImage_W = image.size.width
                captureImage_H = image.size.height
            }
            
            if let cx = centroid_x,
               let cy = centroid_y,
               let captureImage_W = captureImage_W,
               let captureImage_H = captureImage_H,
               let lidarImage_W = lidarImage_W,
               let lidarImage_H = lidarImage_H {
                
                let adjustPoint_x = CGFloat(cx) * (captureImage_W / lidarImage_W)
                let adjustPoint_y = CGFloat(cy) * (captureImage_H / lidarImage_H)
                
                if let fimage = drawRectangleOnImage(image: image, point: CGPoint(x: adjustPoint_x, y: adjustPoint_y)) {
                    image = fimage
                }
            }
            
            handler(image)
        }
    }
}

// MARK: - Common func
extension AVCaptureWithDepth {
    
    // Convert CIImage to UIImage (ref: https://stackoverflow.com/questions/42997462/convert-cmsamplebuffer-to-uiimage)
    func convert(cmage: CIImage) -> UIImage {
         let context = CIContext(options: nil)
         let cgImage = context.createCGImage(cmage, from: cmage.extent)!
         let image = UIImage(cgImage: cgImage)
         return image
    }
    
    // build depth data (ref. https://qiita.com/1024chon/items/74da8d63a8959a8192f5)
    func buildDepthInfo(depthMap: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        let base = CVPixelBufferGetBaseAddress(depthMap)
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        let bindPtr = base?.bindMemory(to: Float32.self, capacity: width * height)
        let bufPtr = UnsafeBufferPointer(start: bindPtr, count: width * height)
        let dArray = Array(bufPtr)
        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)

        depthArray = dArray.map({ $0.isNaN ? 0 : $0 })

    }
    
    func drawRectangleOnImage(image: UIImage, point: CGPoint) -> UIImage? {
        let imageSize = image.size
        let scale: CGFloat = 0
        UIGraphicsBeginImageContextWithOptions(imageSize, false, scale)
        image.draw(at: CGPoint.zero)

        let rectangle = CGRect(x: point.x, y: point.y, width: 30, height: 30)
        UIColor.green.setFill()
        UIRectFill(rectangle)

        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }
}
