/*******************************************************************************
 * Copyright (c) 2021  Carnegie Mellon University
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *******************************************************************************/

import AVFoundation
import CoreMotion
import Photos
import SwiftUI
import UIKit

struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()
    
    var body: some View {
        VStack {
            CameraPreviewView(session: cameraManager.captureSession)
                .edgesIgnoringSafeArea(.all)
            
            Button(action: {
                cameraManager.capturePhoto()
            }) {
                Text("")
                    .foregroundColor(.white)
                    .frame(width: 70, height: 70)
                    .background(Color.white.opacity(0.5))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 5))
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            cameraManager.startSession()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
    }
}

struct CameraPreviewView: UIViewControllerRepresentable {
    class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        var parent: CameraPreviewView
        
        init(parent: CameraPreviewView) {
            self.parent = parent
        }
    }
    
    class PortraitViewController: UIViewController {
        override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
            return .portrait
        }
    }
    
    var session: AVCaptureSession
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = PortraitViewController() // UIViewController()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = viewController.view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        viewController.view.layer.addSublayer(previewLayer)
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if let previewLayer = uiViewController.view.layer.sublayers?.first(where: { $0 is AVCaptureVideoPreviewLayer }) as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiViewController.view.bounds
        }
    }
}

class CameraManager: ObservableObject {
    private var session: AVCaptureSession
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var photoOutput: AVCapturePhotoOutput?
    let captureDelegate = CameraManagerPhotoCaptureDelegate()
    
    init() {
        session = AVCaptureSession()
        configureSession()
    }
    
    private func configureSession() {
        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            return
        }
        
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoDeviceInput!) {
                session.addInput(videoDeviceInput!)
            }
            
            photoOutput = AVCapturePhotoOutput()
            if session.canAddOutput(photoOutput!) {
                session.addOutput(photoOutput!)
            }
        } catch {
            NSLog("Error setting up camera input: \(error)")
        }
    }
    
    func startSession() {
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }
        captureDelegate.startMotionUpdates()
    }
    
    func stopSession() {
        if session.isRunning {
            session.stopRunning()
        }
        captureDelegate.stopMotionUpdates()
    }
    
    func capturePhoto() {
        let photoSettings = AVCapturePhotoSettings()
        photoOutput?.isHighResolutionCaptureEnabled = true
        photoSettings.isHighResolutionPhotoEnabled = true
        photoOutput?.capturePhoto(with: photoSettings, delegate: captureDelegate)
    }
    
    var captureSession: AVCaptureSession {
        return session
    }
}

class CameraManagerPhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let motionManager = CMMotionManager()
    var deviceOrientation: UIDeviceOrientation?
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error = error {
            NSLog("Error capturing photo: \(error)")
            return
        }
        guard let imageData = photo.fileDataRepresentation() else {
            NSLog("Error converting photo to data")
            return
        }
        
        let dateFormatter = DateFormatter()
        let prefix = Bundle.main.infoDictionary!["CFBundleName"] as! String
        dateFormatter.dateFormat = "'\(prefix)-'yyyy'-'MM'-'dd'-'HH'-'mm'-'ss'.jpg'"
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsURL.appendingPathComponent(dateFormatter.string(from: Date()))
        do {
            try addExifData(imageData: imageData).write(to: fileURL)
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
            }) { success, error in
                NSLog("Save ImageData success \(success) error \(error)")
            }
        } catch {
            NSLog("Save ImageData error \(error)")
        }
    }
    
    func addExifData(imageData: Data) -> Data {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil) else {return imageData}
        guard let UTI = CGImageSourceGetType(imageSource) else {return imageData}
        guard let originalMetadata = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {return imageData}
        
        var orientation: CGImagePropertyOrientation
        switch deviceOrientation {
        case .portrait:
            orientation = .right
        case .landscapeLeft:
            orientation = .up
        case .landscapeRight:
            orientation = .down
        case .portraitUpsideDown:
            orientation = .left
        default:
            orientation = .up
        }
        print("orientation=\(orientation)")
        var metadata = originalMetadata
        if let location = ChatData.shared.lastLocation {
            let customMetadata: [CFString: Any] = [
                kCGImagePropertyTIFFDictionary: [
                    kCGImagePropertyTIFFOrientation: orientation.rawValue
                ],
                kCGImagePropertyGPSDictionary: [
                    kCGImagePropertyGPSLatitude: location.lat,
                    kCGImagePropertyGPSLongitude: location.lng,
                    kCGImagePropertyGPSLatitudeRef: location.lat >= 0 ? "N" : "S",
                    kCGImagePropertyGPSLongitudeRef: location.lng >= 0 ? "E" : "W"
                ],
                kCGImagePropertyIPTCDictionary: [
                    kCGImagePropertyIPTCCaptionAbstract: "lat,lng,floor,yaw\n\(location.lat),\(location.lng),\(location.floor),\(location.yaw ?? 0.0)"
                ]
            ]
            metadata.merge(customMetadata) { (_, new) in new }
        } else {
            let customMetadata: [CFString: Any] = [
                kCGImagePropertyTIFFDictionary: [
                    kCGImagePropertyTIFFOrientation: orientation.rawValue
                ],
                kCGImagePropertyIPTCDictionary: [
                    kCGImagePropertyIPTCCaptionAbstract: "No current location"
                ]
            ]
            metadata.merge(customMetadata) { (_, new) in new }
        }
        
        let destinationData = NSMutableData()
        if let destination = CGImageDestinationCreateWithData(destinationData as CFMutableData, UTI, 1, nil) {
            let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)!
            CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
            if CGImageDestinationFinalize(destination) {
                NSLog("addExifData success")
                return destinationData as Data
            }
        }
        return imageData
    }

    func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.2
        motionManager.startDeviceMotionUpdates(to: .main) { motion, error in
            guard let motion = motion else { return }
            let x = motion.gravity.x
            let y = motion.gravity.y
            if abs(y) >= abs(x) {
                self.deviceOrientation = y < 0 ? .portrait : .portraitUpsideDown
            } else {
                self.deviceOrientation = x < 0 ? .landscapeLeft : .landscapeRight
            }
        }
    }

    func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }
}
