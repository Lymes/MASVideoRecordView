//
//  MASCameraService.swift
//  MASVideoRecordView
//
//  Created by leonid.mesentsev on 02/09/21.
//

import AVFoundation


public enum MASCameraServiceError : LocalizedError, Identifiable {
    case denied
    case underlyingError(Error)
    public var id: String { localizedDescription }
    public var errorDescription: String? {
        switch self {
        case .denied: return "Access denied. To use the app you must authorize using your camera."
        case .underlyingError(let error): return error.localizedDescription
        }
    }
}

public class MASCameraService: NSObject, ObservableObject {
    
    // Singleton
    public static let shared = MASCameraService()
    
    // Error subscriptions
    @Published var error: MASCameraServiceError?
    
    // creating session
    let session = AVCaptureSession()
    var cameraDevice: AVCaptureDevice?
    var assetWriter: AVAssetWriter?
    var sessionAtSourceTime: CMTime?
    
    public var minimumZoom: CGFloat = 1.0
    public var maximumZoom: CGFloat = 5.0
    
    private let dataOutputQueue = DispatchQueue(label: "MASCameraService video data queue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    
    public func initialize(_ completion: @escaping (AVCaptureSession?, MASCameraServiceError?) -> Void) {
        //check if the access to the camera is granted
        AVCaptureDevice.requestAccess(for: AVMediaType.video) { [weak self] response in
            //must run on main thread
            DispatchQueue.main.async {
                if response {
                    // access granted - set up the camera session
                    self?.session.sessionPreset = .medium
                    
                    if let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                        self?.cameraDevice = captureDevice
                        //captureDevice.configureDesiredFrameRate(30)
                        do {
                            let input = try AVCaptureDeviceInput(device: captureDevice)
                            self?.session.addInput(input)
                        } catch {
                            print(error.localizedDescription)
                            completion(nil, .underlyingError(error))
                            self?.error = .underlyingError(error)
                        }
                        
                        let output = AVCaptureVideoDataOutput()
                        output.alwaysDiscardsLateVideoFrames = true
                        output.setSampleBufferDelegate(self, queue: self?.dataOutputQueue)
                        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                        output.recommendedVideoSettingsForAssetWriter(writingTo: .mp4)
                        self?.session.addOutput(output)
                        
                        let videoConnection = output.connection(with: .video)
                        videoConnection?.videoOrientation = .portrait
                        if videoConnection?.isVideoMirroringSupported ?? false
                        {
                            videoConnection?.isVideoMirrored = true
                        }
                    }
                    completion(self?.session, nil)
                    self?.error = nil
                } else {
                    // access denied
                    completion(nil, .denied)
                    self?.error = .denied
                }
            }
        }
    }
    
    public func startVideoCapture() {
        self.session.startRunning()
    }
    
    public func stopVideoCapture() {
        self.session.stopRunning()
    }
    
    public func update(scale factor: CGFloat) {
        do {
            try self.cameraDevice?.lockForConfiguration()
            defer { self.cameraDevice?.unlockForConfiguration() }
            self.cameraDevice?.videoZoomFactor = factor
        } catch {
            print("\(error.localizedDescription)")
        }
    }
    
    public func minMaxZoom(_ factor: CGFloat) -> CGFloat {
        return min(min(max(factor, minimumZoom), maximumZoom), self.cameraDevice?.activeFormat.videoMaxZoomFactor ?? 1.0)
    }
    
    
    public func startVideoRecording(filePath: URL) {
        if let assetWriter = try? AVAssetWriter(outputURL: filePath, fileType: AVFileType.mp4) {
            
            let assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey : AVVideoCodecType.h264,
                AVVideoWidthKey : 720,
                AVVideoHeightKey : 1280,
                AVVideoCompressionPropertiesKey : [
                    AVVideoAverageBitRateKey : 4000000,
                    AVVideoAllowFrameReorderingKey: false
                ],
            ])
            
            assetWriterInput.expectsMediaDataInRealTime = true
            //  assetWriterInput.transform = CGAffineTransform(rotationAngle: .pi/2) // Adapt to portrait mode
            
            if assetWriter.canAdd(assetWriterInput) {
                assetWriter.add(assetWriterInput)
            } else {
                print("no input added")
            }
            
            _ = assetWriter.startWriting()
            self.assetWriter = assetWriter
        }
    }
    
    public func stopVideoRecording() {
        if let writer = self.assetWriter {
            for writerInput in writer.inputs {
                if !writerInput.isReadyForMoreMediaData {
                    print("Boiling out from the second STOP...")
                    return
                }
                writerInput.markAsFinished()
            }
            writer.finishWriting { [weak self] in
                guard let self = self else { return }
                self.assetWriter = nil
                self.sessionAtSourceTime = nil
            }
        }
    }
}


extension MASCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        connection.videoOrientation = .portrait
        
        if self.sessionAtSourceTime == nil {
            // start writing
            sessionAtSourceTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
            self.assetWriter?.startSession(atSourceTime: sessionAtSourceTime!)
        }
        
        guard let assetWriterInput = self.assetWriter?.inputs.first else { return }
        
        if assetWriterInput.isReadyForMoreMediaData {

             //if let image = UIImage.imageFromText(text: self.text, attributes: self.attributesForFrame) {
             //self.write(image: image, toBuffer: sampleBuffer)
             // write video buffer
             assetWriterInput.append(sampleBuffer)
             //}
        }
    }
    
}

