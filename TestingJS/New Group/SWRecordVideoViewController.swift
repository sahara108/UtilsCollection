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
  private var isCameraPermissionGranted: Bool = false
  
  let writingVideoQueue = DispatchQueue(label: "Wringting Video")
  let writingVideoQueueKey = DispatchSpecificKey<Void>()
  
  //Controls
  private lazy var backButton: UIButton = {
    let button = UIButton(type: .system).forAutolayout()
    button.setTitle("Back", for: .normal)
    button.setTitleColor(UIColor.black, for: .normal)
    button.addTarget(self, action: #selector(didTouchBackButton), for: .touchUpInside)
    button.tintColor = UIColor.white
    return button
  }()

  // MARK: - Life cycle
  
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor.black
    setupView()
    setupAudioSession()
    addEdgeSwipeGesture()
    writingVideoQueue.setSpecific(key: writingVideoQueueKey, value: ())
    
    sourceAudioFileURL = Bundle.main.url(forResource: "sample", withExtension: "mp3")
  }
  
  override public func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if !didAskCameraPermission {
      checkCameraPermissionAndShowOnboardingIfNeeded()
      didAskCameraPermission = true
    } else if isCameraPermissionGranted {
      stopSession()
    }
    view.bringSubviewToFront(backButton)
  }
  
  override public func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    stopSession()
  }
  
  private func addEdgeSwipeGesture() {
    let edgePan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(screenEdgeSwiped(_:)))
    edgePan.edges = UIRectEdge.right
    view.backgroundColor = UIColor.white
    view.addGestureRecognizer(edgePan)
  }
  
  @objc func screenEdgeSwiped(_ recognizer: UIScreenEdgePanGestureRecognizer) {
    if recognizer.state == .recognized {
    }
  }
  
  private func setupView() {
    addBackButton()
  }
  
  private func setupAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoRecording, options: .defaultToSpeaker)
      try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
    
    }
  }
  
  private func addBackButton() {
    view.addSubview(backButton)
    NSLayoutConstraint.activate([
      backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      backButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      backButton.widthAnchor.constraint(equalToConstant: 44),
      backButton.heightAnchor.constraint(equalToConstant: 44)
      ])
  }
  
  @objc func didTouchBackButton() {
    if isWritterRunning {
      stopPlayback()
      finishVideoWriter()
    } else {
      dismiss(animated: true, completion: nil)
    }
  }
  
  private func setupCamera() {
    guard let captureDevice = AVCaptureDevice.default(for: AVMediaType.video)
      else {
        return
    }
    capturedDevice = captureDevice
    do {
      let input = try AVCaptureDeviceInput(device: captureDevice)
      let videoOutput = AVCaptureVideoDataOutput()
      captureSession = AVCaptureSession()
      if captureSession?.canAddInput(input) == true,
        captureSession?.canAddOutput(videoOutput) == true {
        captureSession?.addInput(input)
        captureSession?.addOutput(videoOutput)
        captureSession?.sessionPreset = AVCaptureSession.Preset.hd1280x720

        videoOutput.setSampleBufferDelegate(self, queue: writingVideoQueue)
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        videoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
        videoPreviewLayer?.frame = view.bounds
        view.layer.insertSublayer(videoPreviewLayer!, at: 0)
        startSession()
        isCameraPermissionGranted = true
      } else {
        //        handleCamera(error: UnknownError())
      }
    } catch let error {
      handleCamera(error: error)
    }
  }
  
  private func handleCamera(error: Error) {
  }
  
  private func handleError(error: Error? = nil) {
    
  }
  
  private var audioPlayer: AVPlayer?
  private func startPlayback() {
    guard let fileURL = sourceAudioFileURL else { return }
    //safe to stop previous player
    stopPlayback()
    
    let player = AVPlayer(url: fileURL)
    player.play()
    audioPlayer = player
  }
  
  private func stopPlayback() {
    audioPlayer?.pause()
    audioPlayer = nil
  }
  
  private func stopSession() {
    captureSession?.stopRunning()
    stopPlayback()
    finishVideoWriter()
  }
  
  private func startSession() {
    captureSession?.startRunning()
    setupVideoWriter()
    startVideoWriterIfNeed()
    startPlayback()
  }
  
  private func checkCameraPermissionAndShowOnboardingIfNeeded() {
    let authStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
    switch authStatus {
    case .authorized:
      setupCamera()
    case .notDetermined:
      requestCameraPermissionAndShowOnboardingIfNeeded()
    case .restricted, .denied:
      handleError()
    }
  }
  
  private func requestCameraPermissionAndShowOnboardingIfNeeded() {
    AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { granted in
      DispatchQueue.main.async { [weak self] in
        if granted {
          self?.setupCamera()
        } else {
          self?.handleError()
        }
      }
    })
  }
  
  private func tempRecordVideoURL() -> URL {
    let tempDir = NSTemporaryDirectory()
    let tempDirURL = URL(fileURLWithPath: tempDir)
    let videoURL = tempDirURL.appendingPathComponent("someVideo")
    return videoURL
  }
  
  private func recordedVideoURL() -> URL {
    let tempDir = NSTemporaryDirectory()
    let tempDirURL = URL(fileURLWithPath: tempDir)
    let videoURL = tempDirURL.appendingPathComponent("recoredVideo")
    return videoURL
  }
  
  var sourceAudioFileURL: URL?
  
  // Writer
  fileprivate var assetWriter: AVAssetWriter?
  fileprivate var videoWriterInput: AVAssetWriterInput?
//  fileprivate var audioWriterInput: AVAssetWriterInput?
  
  private func setupVideoWriter() {
    guard assetWriter == nil else {
      return
    }
    
    do {
      try? FileManager.default.removeItem(at: tempRecordVideoURL())
      let writer = try AVAssetWriter(outputURL: tempRecordVideoURL(), fileType: .mp4)
      let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecH264,
                                                                              AVVideoWidthKey: NSNumber(value: 720),
                                                                              AVVideoHeightKey: NSNumber(value: 1280)])
      
      var channelLayout = AudioChannelLayout()
      memset(&channelLayout, 0, MemoryLayout<AudioChannelLayout>.size);
      channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
//      let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVSampleRateKey: NSNumber(value: 44100.0),
//                                                                              AVFormatIDKey: NSNumber(value: kAudioFormatMPEG4AAC),
//                                                                              AVEncoderBitRateKey: NSNumber(value: 64000),
//                                                                              AVChannelLayoutKey: NSData(bytes:&channelLayout, length:MemoryLayout<AudioChannelLayout>.size)])
      if writer.canAdd(videoInput) {
        writer.add(videoInput)
        assetWriter = writer
        videoWriterInput = videoInput
        //      audioWriterInput = audioInput
        
        isWritterRunning = false //ready to write video
      }
//      if writer.canAdd(audioInput) {
//        writer.add(audioInput)
//      }
    } catch {
      
    }
  }
  
  private func executeWritingVideoJob(_ job: @escaping ()->()) {
    writingVideoQueue.async {
      job()
    }
  }
  
  private var isWritterRunning = false
  fileprivate var waitingFirstBuffer = true
//  fileprivate var audioFile: AVAudioFile?
  fileprivate func startVideoWriterIfNeed() {
    executeWritingVideoJob { [weak self] in
      guard let this = self else { return }
      guard let sourceAudioURL = this.sourceAudioFileURL else { return }
      guard !this.isWritterRunning else {
        return
      }
      
      this.assetWriter?.startWriting()
      this.isWritterRunning = true
      
      //let wait untile both audio and video input is ready
      do {
//        let audioFile = try AVAudioFile(forReading: sourceAudioURL)
        this.waitingFirstBuffer = true
//        this.audioFile = audioFile
      } catch {
        this.finishVideoWriter()
      }
    }
  }
  
  fileprivate func finishVideoWriter() {
    executeWritingVideoJob { [weak self] in
      guard let this = self else { return }
      guard this.isWritterRunning else {
        return
      }
      
//      this.audioWriterInput?.markAsFinished()
      this.videoWriterInput?.markAsFinished()
      this.assetWriter?.finishWriting { [weak this] in
        this?.didFinishRecordingVideo()
      }
      
      this.isWritterRunning = false
      this.waitingFirstBuffer = false
    }
  }
  
  fileprivate func writeBuffer(buffer: CMSampleBuffer) {
    executeWritingVideoJob { [weak self] in
      guard let this = self else { return }
      let cancel = {
        this.stopSession()
      }
//      guard let audioFile = this.audioFile else {
//        cancel()
//        return
//      }
      
//      guard let audioPCMBuffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat,
//                                                  frameCapacity: 1) else {
//                                                    cancel()
//                                                    return
//      }
//
      //get the audio buffer
//      var timingInfo: CMSampleTimingInfo = CMSampleTimingInfo.init()
//      CMSampleBufferGetSampleTimingInfo(buffer, at: CMItemIndex(bitPattern: 0), timingInfoOut: &timingInfo)
      do{
        if this.waitingFirstBuffer {
          this.waitingFirstBuffer = false
          this.assetWriter?.startSession(atSourceTime: CMTime.zero)
        } else {
          if this.videoWriterInput?.isReadyForMoreMediaData == true {
            this.videoWriterInput?.append(buffer)
          }
        }
//        try audioFile.read(into: audioPCMBuffer, frameCount: 1)
//        let audioDataFormat = audioPCMBuffer.format
//        if let audioSampleBuffer = this.processAudioData(audioData: audioPCMBuffer.audioBufferList, audioFormat: audioDataFormat.formatDescription, timingInfo: timingInfo, framesNumber: audioPCMBuffer.frameLength, mono: audioPCMBuffer.audioBufferList.pointee.mNumberBuffers == 1) {
//          this.audioWriterInput?.append(audioSampleBuffer)
//        }
      } catch {
        // show error?
        cancel()
      }
      
    }
  }
  
  fileprivate func didFinishRecordingVideo() {
    mergeVideo()
  }
  
  fileprivate func mergeVideo() {
    let mixComposition : AVMutableComposition = AVMutableComposition()
    var mutableCompositionVideoTrack : [AVMutableCompositionTrack] = []
    var mutableCompositionAudioTrack : [AVMutableCompositionTrack] = []
    let totalVideoCompositionInstruction : AVMutableVideoCompositionInstruction = AVMutableVideoCompositionInstruction()
    
    
    //start merge
    let aVideoAsset : AVAsset = AVAsset(url: tempRecordVideoURL())
    let aAudioAsset : AVAsset = AVAsset(url: self.sourceAudioFileURL!)
    
    mutableCompositionVideoTrack.append(mixComposition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: kCMPersistentTrackID_Invalid)!)
    mutableCompositionAudioTrack.append( mixComposition.addMutableTrack(withMediaType: AVMediaType.audio, preferredTrackID: kCMPersistentTrackID_Invalid)!)
    
    let aVideoAssetTrack : AVAssetTrack = aVideoAsset.tracks[0]
    let aAudioAssetTrack : AVAssetTrack = aAudioAsset.tracks[0]
    
    do{
      try mutableCompositionVideoTrack[0].insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: aVideoAssetTrack.timeRange.duration), of: aVideoAssetTrack, at: CMTime.zero)
      
      //In my case my audio file is longer then video file so i took videoAsset duration
      //instead of audioAsset duration
      
      try mutableCompositionAudioTrack[0].insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: aVideoAssetTrack.timeRange.duration), of: aAudioAssetTrack, at: CMTime.zero)
      
      //Use this instead above line if your audiofile and video file's playing durations are same
      
      //            try mutableCompositionAudioTrack[0].insertTimeRange(CMTimeRangeMake(kCMTimeZero, aVideoAssetTrack.timeRange.duration), ofTrack: aAudioAssetTrack, atTime: kCMTimeZero)
      
    }catch{
      
    }
    
    totalVideoCompositionInstruction.timeRange = CMTimeRangeMake(start: CMTime.zero,duration: aVideoAssetTrack.timeRange.duration )
    
    let mutableVideoComposition : AVMutableVideoComposition = AVMutableVideoComposition()
    mutableVideoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
    
    mutableVideoComposition.renderSize = CGSize(width: 720, height: 1280)
    
    //        playerItem = AVPlayerItem(asset: mixComposition)
    //        player = AVPlayer(playerItem: playerItem!)
    //
    //
    //        AVPlayerVC.player = player
    
    
    
    //find your video on this URl
    let savePathUrl : NSURL = NSURL(fileURLWithPath: NSHomeDirectory() + "/Documents/newVideo.mp4")
    
    let assetExport: AVAssetExportSession = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality)!
    assetExport.outputFileType = AVFileType.mp4
    assetExport.outputURL = recordedVideoURL()
    assetExport.shouldOptimizeForNetworkUse = true
    
    assetExport.exportAsynchronously { () -> Void in
      switch assetExport.status {
        
      case AVAssetExportSession.Status.completed:
        
        //Uncomment this if u want to store your video in asset
        
        //let assetsLib = ALAssetsLibrary()
        //assetsLib.writeVideoAtPathToSavedPhotosAlbum(savePathUrl, completionBlock: nil)
        
        print("success")
      case  AVAssetExportSession.Status.failed:
        print("failed \(assetExport.error)")
      case AVAssetExportSession.Status.cancelled:
        print("cancelled \(assetExport.error)")
      default:
        print("complete")
      }
    }
  }
}

extension SWRecordVideoViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    
  }
  
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    writeBuffer(buffer: sampleBuffer)
  }
  
  func processAudioData(audioData: UnsafePointer<AudioBufferList>, audioFormat inputFormat: CMFormatDescription, timingInfo: CMSampleTimingInfo, framesNumber: UInt32, mono: Bool) -> CMSampleBuffer? {
    var sbuf : CMSampleBuffer?
    var status : OSStatus?
    var format: CMFormatDescription?
    
    let audioFormat = CMAudioFormatDescriptionGetStreamBasicDescription(inputFormat)
    var timing = timingInfo
    
    var acl = AudioChannelLayout();
    bzero(&acl, MemoryLayout<AudioChannelLayout>.size);
    acl.mChannelLayoutTag = mono ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo;

    status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: audioFormat!, layoutSize: MemoryLayout<AudioChannelLayout>.size, layout: &acl, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
    if status != noErr {
      print("Error CMAudioFormatDescriptionCreater :\(String(describing: status?.description))")
      return nil
    }

    status = CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil, formatDescription: format, sampleCount: CMItemCount(framesNumber), sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sbuf)
    if status != noErr {
      print("Error CMSampleBufferCreate :\(String(describing: status?.description))")
      return nil
    }

    guard let buf = sbuf else { return nil}
    status = CMSampleBufferSetDataBufferFromAudioBufferList(buf, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: audioData)
    let audiobufferListRaw: AudioBufferList = audioData.pointee
    if status != noErr {
      print("Error cCMSampleBufferSetDataBufferFromAudioBufferList :\(String(describing: status?.description))")
      return nil
    }
    
    return buf
  }

}

