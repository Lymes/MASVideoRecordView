//
//  MASVideoRecordView.swift
//  MASVideoRecordView
//
//  Created by leonid.mesentsev on 02/09/21.
//

import UIKit
import SwiftUI
import AVFoundation


public struct MASVideoRecordView: UIViewRepresentable {
    
    public func makeUIView(context: UIViewRepresentableContext<MASVideoRecordView>) -> PreviewView {
        let recordingView = PreviewView(/*showingAlert: self.$showingAlert*/)
        return recordingView
    }
    
    public func updateUIView(_ uiViewController: PreviewView, context: UIViewRepresentableContext<MASVideoRecordView>) {
        UIView.setAnimationsEnabled(false)
        uiViewController.checkOrientation()
        UIView.setAnimationsEnabled(true)
    }
}


public class PreviewView: UIView {
    
    private var videoPreview = AVCaptureVideoPreviewLayer()
    private var lastZoomFactor: CGFloat = 1.0
    
    init() {
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func checkOrientation() {
        let orientation: UIDeviceOrientation = UIDevice.current.orientation
        self.videoPreview.connection?.videoOrientation = {
              switch (orientation) {
              case .portrait:
                  return .portrait
              case .landscapeRight:
                  return .landscapeLeft
              case .landscapeLeft:
                  return .landscapeRight
              default:
                  return .portrait
              }
          }()
    
        let bounds = self.bounds
        self.videoPreview.frame = CGRect(x: 0, y: 0, width: bounds.size.height, height: bounds.size.width)
    }
    
    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        MASCameraService.shared.initialize { session, error in
            if let s = session {
                let pinchRecognizer = UIPinchGestureRecognizer(target: self, action:#selector(self.pinch(_:)))
                self.addGestureRecognizer(pinchRecognizer)
                
                self.videoPreview = AVCaptureVideoPreviewLayer(session: s)
                self.videoPreview.frame = self.frame
                self.videoPreview.videoGravity = AVLayerVideoGravity.resizeAspectFill
                self.videoPreview.position = CGPoint(x: self.frame.midX, y: self.frame.midY);
                self.layer.addSublayer(self.videoPreview)
                MASCameraService.shared.startVideoCapture()
            }
        }
    }

    @objc func pinch(_ pinch: UIPinchGestureRecognizer) {
        let newScaleFactor = MASCameraService.shared.minMaxZoom(pinch.scale * lastZoomFactor)
        switch pinch.state {
        case .began: fallthrough
        case .changed: MASCameraService.shared.update(scale: newScaleFactor)
        case .ended:
            lastZoomFactor = MASCameraService.shared.minMaxZoom(newScaleFactor)
            MASCameraService.shared.update(scale: lastZoomFactor)
        default: break
        }
    }
}
