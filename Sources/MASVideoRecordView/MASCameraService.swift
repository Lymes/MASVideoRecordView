//
//  MASCameraService.swift
//  MASVideoRecordView
//
//  Created by leonid.mesentsev on 02/09/21.
//

import AVFoundation
import UIKit


public typealias MASFrameCallback = (_ buffer: CMSampleBuffer) -> CMSampleBuffer


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


public enum MASRecordingState {
    case idle
    case starting
    case started
    case stopping
}

public typealias MASStopCompletion = () -> Void

public class MASCameraService: NSObject, ObservableObject {
    
    // Singleton
    public static let shared = MASCameraService()
    
    // subscriptions
    @Published public var error: MASCameraServiceError?
    @Published public private(set) var state: MASRecordingState = .idle
    
    // creating session
    let session = AVCaptureSession()
    var cameraDevice: AVCaptureDevice?
    var assetWriter: AVAssetWriter?
    var sessionAtSourceTime: CMTime? = nil
    var frameCallback: MASFrameCallback? = nil
    
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
                            print("MASCameraService", error.localizedDescription)
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
                        //videoConnection?.videoOrientation = .portrait
                        if videoConnection?.isVideoMirroringSupported ?? false
                        {
                            videoConnection?.isVideoMirrored = false
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
            print("\(self): \(error.localizedDescription)")
        }
    }
    
    
    public func minMaxZoom(_ factor: CGFloat) -> CGFloat {
        return min(min(max(factor, minimumZoom), maximumZoom), self.cameraDevice?.activeFormat.videoMaxZoomFactor ?? 1.0)
    }
    
    
    public func startVideoRecording(file: URL, frameCallback: MASFrameCallback? = nil) {
        guard self.state == .idle else { return }
        print("\(self): starting write to", file)
        self.frameCallback = frameCallback
        self.state = .starting
        do { try FileManager.default.removeItem(at: file) } catch {}
        if let assetWriter = try? AVAssetWriter(outputURL: file, fileType: AVFileType.mp4) {
            
            let orientation: AVCaptureVideoOrientation = UIDevice.current.orientation.getAVOrientation()
            
            if let videoConnection = session.outputs.first?.connection(with: .video) {
                videoConnection.videoOrientation = orientation
            }
            
            var width = 720
            var height = 1280
            switch orientation {
            case .landscapeLeft, .landscapeRight:
                width = 1280; height = 720
            case .portrait, .portraitUpsideDown:
                width = 720; height = 1280
            @unknown default:
                break
            }
            
            let assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey : AVVideoCodecType.h264,
                AVVideoHeightKey : height,
                AVVideoWidthKey : width,
                AVVideoCompressionPropertiesKey : [
                    AVVideoAverageBitRateKey : 4000000,
                    AVVideoAllowFrameReorderingKey: false
                ],
            ])
            
            assetWriterInput.expectsMediaDataInRealTime = true
            if assetWriter.canAdd(assetWriterInput) {
                assetWriter.add(assetWriterInput)
            } else {
                print("\(self): no input added")
            }
            
            _ = assetWriter.startWriting()
            self.assetWriter = assetWriter
            self.state = .started
        }
    }
    
    public func stopVideoRecording(_ completion: MASStopCompletion? = nil) {
        guard self.state == .started else { return }
        self.state = .stopping
        if let writer = self.assetWriter {
            for writerInput in writer.inputs {
                if !writerInput.isReadyForMoreMediaData {
                    print("\(self): boiling out from the second STOP...")
                    return
                }
                writerInput.markAsFinished()
            }
            writer.finishWriting { [weak self] in
                guard let self = self else { return }
                self.assetWriter = nil
                self.sessionAtSourceTime = nil
                DispatchQueue.main.async {
                    self.state = .idle
                    completion?()
                    print("\(self): finished writing.")
                }
            }
        } else {
            self.state = .idle
        }
    }
    
}


extension UIDeviceOrientation {
    
    func getAVOrientation() -> AVCaptureVideoOrientation {
        switch (self) {
        case .portrait:
            return .portrait
        case .landscapeRight:
            return .landscapeLeft
        case .landscapeLeft:
            return .landscapeRight
        default:
            return .portrait
        }
    }
}


extension MASCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard self.assetWriter != nil else { return }
        
        if self.sessionAtSourceTime == nil {
            // start writing
            sessionAtSourceTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
            self.assetWriter?.startSession(atSourceTime: sessionAtSourceTime!)
        }
        
        guard let assetWriterInput = self.assetWriter?.inputs.first else { return }
        
        if assetWriterInput.isReadyForMoreMediaData {
            var inputBuffer = sampleBuffer
            if let callback = self.frameCallback {
                inputBuffer = callback(sampleBuffer)
            }
            assetWriterInput.append(inputBuffer)
        }
    }
    
}

