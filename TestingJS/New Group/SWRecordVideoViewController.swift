//
//  SWRecordVideoViewController.swift
//  TestingJS
//
//  Created by Anh Tuan Nguyen on 19/11/18.
//  Copyright © 2018 Nguyen Tuan. All rights reserved.
//

import UIKit
import AVFoundation

extension UIView {
  func forAutolayout() -> Self {
    translatesAutoresizingMaskIntoConstraints = false
    return self
  }
}

class SWRecordVideoViewController: UIViewController {
  //Camera related
  private var captureSession: AVCaptureSession?
  private var capturedDevice: AVCaptureDevice?
  private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
  private var didAskCameraPermission: Bool = false
  private var isCameraPermissionGranted: Bool = false {
    didSet {
      startIfPossible()
    }
  }
  private var isMicrophonePermissionGranted: Bool = false {
    didSet {
      startIfPossible()
    }
  }
  
  //Controls
  private lazy var backButton: UIButton = {
    let button = UIButton(type: .system).forAutolayout()
    button.setImage(UIImage(named: "back")!, for: .normal)
    button.addTarget(self, action: #selector(didTouchBackButton), for: .touchUpInside)
    return button
  }()
  
  private lazy var recordButton: UIButton = {
    let button = UIButton(type: .custom).forAutolayout()
    button.setImage(UIImage(named: "record")!, for: .normal)
    let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(SWRecordVideoViewController.longPressRecordButton))
    button.addGestureRecognizer(longPressGesture)
    return button
  }()
  
  private lazy var flipCameraButton: UIButton = {
    let button = UIButton(type: .custom).forAutolayout()
    button.setImage(UIImage(named: "flip_camera")!, for: .normal)
    button.addTarget(self, action: #selector(SWRecordVideoViewController.didTouchFlipCameraButton), for: .touchUpInside)
    return button
  }()

  private lazy var recorder = SWRecorder()
  // MARK: - Life cycle
  
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor.black
    setupView()
    setupAudioSession()
    captureSession = AVCaptureSession()
    videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
    videoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
    sessionQueue.async { [weak self] in
      self?.setupCameraSession()
    }
  }
  
  override public func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    checkPermissionAndShowOnboardingIfNeeded()
    view.bringSubviewToFront(backButton)
  }
  
  override public func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    stopSession()
  }
  
  private func setupView() {
    addBackButton()
    addRecordButton()
    addFlipCameraButton()
  }
  
  private func addBackButton() {
    view.addSubview(backButton)
    NSLayoutConstraint.activate([
      backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      backButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
      backButton.widthAnchor.constraint(equalToConstant: 44),
      backButton.heightAnchor.constraint(equalToConstant: 44)
      ])
  }
  
  @objc func didTouchBackButton() {
    if recorder.isRunning {
      recorder.finish()
    } else {
      dismiss(animated: true, completion: nil)
    }
  }
  
  private func addRecordButton() {
    view.addSubview(recordButton)
    NSLayoutConstraint.activate([
      recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 0),
      recordButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
      recordButton.widthAnchor.constraint(equalToConstant: 60),
      recordButton.heightAnchor.constraint(equalToConstant: 60)
      ])
  }
  
  @objc func longPressRecordButton(longPressGesture: UILongPressGestureRecognizer) {
    //begin record
    switch longPressGesture.state {
    case .began:
      beginTouchRecord()
    case .cancelled, .ended:
      endTouchRecord()
    default:
      break
    }
  }
  
  @objc func beginTouchRecord() {
    do {
      try recorder.prepare()
      try recorder.beginWriting()
    } catch _ {
      //TODO: something went wrong, show alert
    }
  }
  
  @objc func endTouchRecord() {
    do {
      try recorder.pauseWriting()
    } catch {
      
    }
  }
  
  @objc func didTouchRecordButton() {
    
  }
  
  private func addFlipCameraButton() {
    view.addSubview(flipCameraButton)
    NSLayoutConstraint.activate([
      flipCameraButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      flipCameraButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
      flipCameraButton.widthAnchor.constraint(equalToConstant: 44),
      flipCameraButton.heightAnchor.constraint(equalToConstant: 44)
      ])
  }
  @objc func didTouchFlipCameraButton() {
    flipCameraButton.isEnabled = false
    sessionQueue.async { [weak self] in
      self?.changeCamera(completion: { (s) in
        self?.flipCameraButton.isEnabled = true
      })
    }
  }
  
  // MARK: Session Management
  private enum SessionSetupResult {
    case success
    case notAuthorized
    case configurationFailed
  }
  private lazy var sessionQueue = {
    return recorder.writingVideoQueue
  }()
  
  private var setupResult: SessionSetupResult = .success
  private var currentDeviceInput: AVCaptureDeviceInput?
  private var videoCaptureOutput: AVCaptureVideoDataOutput?
  private var audioCaptureOutput: AVCaptureAudioDataOutput?
  private func setupAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoRecording, options: .defaultToSpeaker)
      try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
    }
  }
  
  private func setupCameraSession() {
    guard let captureDevice = getDevice(position: .front),
      let microphoneDevice = AVCaptureDevice.default(for: .audio),
      setupResult == .success
      else {
        return
    }
    capturedDevice = captureDevice
    do {
      let input = try AVCaptureDeviceInput(device: captureDevice)
      let audioDeviceInput = try AVCaptureDeviceInput(device: microphoneDevice)
      let videoOutput = AVCaptureVideoDataOutput()
      videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA] as [String: Any]
      let audioOutput = AVCaptureAudioDataOutput()
      captureSession?.beginConfiguration()
      captureSession?.sessionPreset = AVCaptureSession.Preset.hd1280x720
      if captureSession?.canAddInput(input) == true,
        captureSession?.canAddInput(audioDeviceInput) == true,
        captureSession?.canAddOutput(videoOutput) == true,
        captureSession?.canAddOutput(audioOutput) == true {
        captureSession?.addInput(input)
        captureSession?.addInput(audioDeviceInput)
        captureSession?.addOutput(videoOutput)
        captureSession?.addOutput(audioOutput)

        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global())
        audioOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global())
        DispatchQueue.main.async {
          self.setupVideoPreviewLayer()
        }
        
        captureSession?.commitConfiguration()
        captureSession?.startRunning()
        currentDeviceInput = input
        videoCaptureOutput = videoOutput
        audioCaptureOutput = audioOutput
      } else {
        setupResult = .configurationFailed
        captureSession?.commitConfiguration()
        handleUnableSetupCamera(nil)
      }
    } catch let error {
      handleUnableSetupCamera(error)
    }
  }
  
  private func setupVideoPreviewLayer() {
    videoPreviewLayer?.frame = view.bounds
    view.layer.insertSublayer(videoPreviewLayer!, at: 0)
    
    /*
     Dispatch video streaming to the main queue because AVCaptureVideoPreviewLayer is the backing layer for PreviewView.
     You can manipulate UIView only on the main thread.
     Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
     on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
     
     Use the status bar orientation as the initial video orientation. Subsequent orientation changes are
     handled by CameraViewController.viewWillTransition(to:with:).
     */
    let statusBarOrientation = UIApplication.shared.statusBarOrientation
    var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
    if statusBarOrientation != .unknown {
      if let videoOrientation = AVCaptureVideoOrientation(rawValue: statusBarOrientation.rawValue) {
        initialVideoOrientation = videoOrientation
      }
    }
    
    self.videoPreviewLayer?.connection?.videoOrientation = initialVideoOrientation
  }
  
  private func changeCamera(completion: @escaping (Bool) -> ()) {
    sessionQueue.async { [weak self] in
      guard let this = self else { return }
      guard let currentVideoInput = this.currentDeviceInput else { return }
      let currentVideoDevice = currentVideoInput.device
      let currentPosition = currentVideoDevice.position
      
      let preferredPosition: AVCaptureDevice.Position
      let preferredDeviceType: AVCaptureDevice.DeviceType
      
      switch currentPosition {
      case .unspecified, .front:
        preferredPosition = .back
        preferredDeviceType = .builtInWideAngleCamera
      case .back:
        preferredPosition = .front
        preferredDeviceType = .builtInWideAngleCamera
      }
      
      let newVideoDevice: AVCaptureDevice? = AVCaptureDevice.default(preferredDeviceType, for: .video, position: preferredPosition)
      var success = true
      if let videoDevice = newVideoDevice {
        do {
          let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
          
          this.captureSession?.beginConfiguration()
          
          // Remove the existing device input first, since the system doesn't support simultaneous use of the rear and front cameras.
          this.captureSession?.removeInput(currentVideoInput)
          
          if this.captureSession?.canAddInput(videoDeviceInput) == true {
            this.captureSession?.addInput(videoDeviceInput)
            this.currentDeviceInput = videoDeviceInput
          } else {
            // If we can't add new device, readd the current input device
            success = false
            this.captureSession?.addInput(currentVideoInput)
          }

          this.captureSession?.commitConfiguration()
        } catch {
          success = false
        }
      }
      
      DispatchQueue.main.async {
        completion(success)
      }
    }
  }
  
  private func stopSession() {
    sessionQueue.async { [weak self] in
      self?.captureSession?.stopRunning()
      self?.recorder.finish()
    }
  }
  
  // MARK: - Camera Devices
  func getDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
    let output: AVCaptureDevice?
    if #available(iOS 10.2, *) {
      if let device = AVCaptureDevice.default(.builtInDualCamera,
                                              for: .video, position: position) {
        output = device
      } else {
        output = AVCaptureDevice.default(.builtInWideAngleCamera,
                                         for: .video, position: position)
      }
    } else {
      // Fallback on earlier versions
      output = AVCaptureDevice.default(.builtInWideAngleCamera,
                              for: .video, position: position)
    }

    return output
  }
  
  // MARK: - Permission
  fileprivate struct PermissionError: OptionSet {
    let rawValue: Int
    static let camera = PermissionError(rawValue: 1 << 0)
    static let microphone = PermissionError(rawValue: 1 << 1)
  }
  private func checkPermissionAndShowOnboardingIfNeeded() {
    let videoStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
    let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    isMicrophonePermissionGranted = audioStatus == .authorized
    isCameraPermissionGranted = videoStatus == .authorized
    if (videoStatus == .restricted || videoStatus == .denied) {
      handlePermissionError(.camera)
    } else if (audioStatus == .restricted || audioStatus == .denied) {
      handlePermissionError(.microphone)
    } else {
      //request permission and continue
      if videoStatus == .notDetermined {
        requestPermissionAndShowOnboardingIfNeeded(type: .video)
      }
      if audioStatus == .notDetermined {
        requestPermissionAndShowOnboardingIfNeeded(type: .audio)
      }
    }
  }
  
  private func requestPermissionAndShowOnboardingIfNeeded(type: AVMediaType) {
    AVCaptureDevice.requestAccess(for: type, completionHandler: { granted in
      DispatchQueue.main.async { [weak self] in
        if granted {
          if type == .video {
            self?.isCameraPermissionGranted = true
          } else if type == .audio {
            self?.isMicrophonePermissionGranted = true
          }
        } else {
          self?.handlePermissionError(.camera)
        }
      }
    })
  }
  
  private func startIfPossible() {
    if isCameraPermissionGranted && isMicrophonePermissionGranted {
      sessionQueue.async { [weak self] in
        self?.setupCameraSession()
      }
    }
  }
}

extension SWRecordVideoViewController {
  // MARK: - Error Handling
  fileprivate func handleUnableSetupCamera(_ error: Error?) {
  }
  
  fileprivate func handlePermissionError(_ error: PermissionError) {
    
  }
}

extension SWRecordVideoViewController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
  func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    var mode: CMAttachmentMode = 0
    let reason = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_DroppedFrameReason, attachmentModeOut: &mode)
    print("reason \(String(describing: reason))") // Optional(OutOfBuffers)
  }
  
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer) else {
      return
    }
    if output == videoCaptureOutput {
      recorder.writeVideoBuffer(sampleBuffer)
    } else if output == audioCaptureOutput {
      recorder.writeAudioBuffer(sampleBuffer)
    }
  }
}

extension SWRecordVideoViewController: SWRecorderOutput {
  func recorderReadyForCollection() {
    
  }
  
  func recorderDidFinish(withFile fileUrl: URL) {
    
  }
}

