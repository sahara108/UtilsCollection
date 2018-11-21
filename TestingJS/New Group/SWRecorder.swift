//
//  SWRecorder.swift
//  TestingJS
//
//  Created by Anh Tuan Nguyen on 20/11/18.
//  Copyright © 2018 Nguyen Tuan. All rights reserved.
//

import AVFoundation

protocol SWRecorderOutput: class {
  func recorderFail(withError error: SWRecorderError)
}

enum SWRecorderError: Error {
  case systemError(_ error: Error)
  case failedToStartVideo
  case failedToStartAudio
  case otherWritterIsRunning
  case notPrepared
}

final class SWRecorder: NSObject {
  let writingVideoQueue = OS_dispatch_queue_serial(label: "Recorder Queue")
  
  weak var output: SWRecorderOutput?
  var isRunning = false
  
  override init() {
    super.init()

  }
  
  private func executeWritingVideoJob(_ job: @escaping ()->()) {
    writingVideoQueue.async {
      job()
    }
  }
  
  // Writer
  fileprivate var assetWriter: AVAssetWriter?
  fileprivate var videoWriterInput: AVAssetWriterInput?
  fileprivate var audioWriterInput: AVAssetWriterInput?
  func prepare() throws {
    guard assetWriter == nil, !isRunning else {
      throw SWRecorderError.otherWritterIsRunning
    }
    
    //first reset all variables
    reset()
    
    do {
      try? FileManager.default.removeItem(at: tempRecordVideoURL())
      let writer = try AVAssetWriter(outputURL: tempRecordVideoURL(), fileType: .mov)
      writer.shouldOptimizeForNetworkUse = true
      let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecH264,
                                                                              AVVideoWidthKey: NSNumber(value: 1280),
                                                                              AVVideoHeightKey: NSNumber(value: 720)])
      videoInput.expectsMediaDataInRealTime = true
      videoInput.transform = CGAffineTransform.init(rotationAngle: CGFloat.pi * 0.5)
      
      var channelLayout = AudioChannelLayout()
      memset(&channelLayout, 0, MemoryLayout<AudioChannelLayout>.size);
      channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
      let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVSampleRateKey: NSNumber(value: 44100.0),
                                                                              AVFormatIDKey: NSNumber(value: kAudioFormatMPEG4AAC),
                                                                              AVEncoderBitRateKey: NSNumber(value: 64000),
                                                                              AVChannelLayoutKey: NSData(bytes:&channelLayout, length:MemoryLayout<AudioChannelLayout>.size)])
      audioInput.expectsMediaDataInRealTime = true
      if writer.canAdd(videoInput) {
        writer.add(videoInput)
      } else {
        throw SWRecorderError.failedToStartVideo
      }
      if writer.canAdd(audioInput) {
        writer.add(audioInput)
      } else {
        throw SWRecorderError.failedToStartAudio
      }
      assetWriter = writer
      videoWriterInput = videoInput
      audioWriterInput = audioInput
      isRunning = true
      acceptIncomingBuffer = false
    } catch let error as SWRecorderError {
      throw error
    } catch let otherError {
      throw SWRecorderError.systemError(otherError)
    }
  }
  
  private var acceptIncomingBuffer = false
  func beginWriting() throws {
    guard isRunning else {
      throw SWRecorderError.notPrepared
    }
    executeWritingVideoJob { [weak self] in
      guard let this = self else { return }
      this.acceptIncomingBuffer = true
    }
  }
  
  func pauseWriting() throws {
    guard isRunning else {
      throw SWRecorderError.notPrepared
    }
    executeWritingVideoJob { [weak self] in
      guard let this = self else { return }
      this.acceptIncomingBuffer = false
      this.videoLastTimingInfo?.save()
      this.audioLastTimingInfo?.save()
    }
  }
  
  func finish() {
    executeWritingVideoJob { [weak self] in
      guard let this = self, this.isRunning else { return }
      
      this.videoWriterInput?.markAsFinished()
      this.audioWriterInput?.markAsFinished()
      this.assetWriter?.endSession(atSourceTime: this.videoLastTimingInfo?.last ?? CMTime.zero)
      this.assetWriter?.finishWriting { [weak this] in
        this?.didFinishRecordingVideo()
      }
      this.isRunning = false
      this.reset()
    }
  }
  
  private func reset() {
    //reset variable
    self.videoWriterInput = nil
    self.audioWriterInput = nil
    self.assetWriter = nil
    self.acceptIncomingBuffer = false
    self.videoLastTimingInfo = nil
    self.audioLastTimingInfo = nil
  }
  
  private class SaveStateTimingInfo {
    var last: CMTime?
    var oldDiff: CMTime?
    var diff: CMTime?
    var pause: CMTime?
    
    func reset() {
      last = nil
      diff = nil
      pause = nil
      oldDiff = nil
    }
    
    func save() {
      pause = last
      oldDiff = diff
      diff = nil
    }
  }
  private var videoLastTimingInfo: SaveStateTimingInfo?
  private var audioLastTimingInfo: SaveStateTimingInfo?
  func writeVideoBuffer(_ buffer: CMSampleBuffer) {
    guard acceptIncomingBuffer else {
      return
    }
    executeWritingVideoJob { [weak self] in
      guard let this = self else { return }
      let bufferTimestamp = CMSampleBufferGetPresentationTimeStamp(buffer)
      if this.assetWriter?.status == .unknown {
        this.assetWriter?.startWriting()
        this.assetWriter?.startSession(atSourceTime: bufferTimestamp)
        //create last info for video and audio buffer
        this.videoLastTimingInfo = SaveStateTimingInfo()
        this.audioLastTimingInfo = SaveStateTimingInfo()
      } else if this.assetWriter?.status == .writing, this.videoWriterInput?.isReadyForMoreMediaData == true, let outBuffer = this.processBuffer(buffer, timingInfo: this.videoLastTimingInfo) {
        autoreleasepool(invoking: { () -> () in
          this.videoWriterInput?.append(outBuffer)
        })
        this.videoLastTimingInfo?.last = bufferTimestamp
      } else {
        let error = this.assetWriter?.error
        print("what is this: \(String(describing: error))")
      }
    }
  }
  
  func writeAudioBuffer(_ buffer: CMSampleBuffer) {
      guard acceptIncomingBuffer else { return }
      executeWritingVideoJob { [weak self] in
        guard let this = self else { return }
        let bufferTimestamp = CMSampleBufferGetPresentationTimeStamp(buffer)
        if this.assetWriter?.status == .writing, this.audioWriterInput?.isReadyForMoreMediaData == true, let outbuffer = this.processBuffer(buffer, timingInfo: this.audioLastTimingInfo) {
          this.audioWriterInput?.append(outbuffer)
        }
        this.audioLastTimingInfo?.last = bufferTimestamp
      }
  }
  
  private func processBuffer(_ buffer: CMSampleBuffer, timingInfo info: SaveStateTimingInfo?) -> CMSampleBuffer? {
    let bufferTimestamp = CMSampleBufferGetPresentationTimeStamp(buffer)
    if let lastPauseTime = info?.pause, info?.diff == nil {
      info?.diff = bufferTimestamp - lastPauseTime + (info?.oldDiff ?? CMTime.zero)
    }

    if let diff = info?.diff, CMTimeGetSeconds(diff) > 0 {
      let newTimestamp = bufferTimestamp - diff + CMTime(seconds: 1.0/30, preferredTimescale: bufferTimestamp.timescale)

      var count: CMItemCount = 0
      CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count);
      var pInfo = CMSampleTimingInfo.invalid
      CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: count, arrayToFill: &pInfo, entriesNeededOut: &count)
      for _ in 0..<count {
        pInfo.decodeTimeStamp = newTimestamp; // kCMTimeInvalid if in sequence
        pInfo.presentationTimeStamp = newTimestamp;
      }
      var sout: CMSampleBuffer? = nil
      CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorMalloc, sampleBuffer: buffer, sampleTimingEntryCount: count, sampleTimingArray: &pInfo, sampleBufferOut: &sout)

      return sout
    } else {
      return buffer
    }
  }
  
  fileprivate func didFinishRecordingVideo() {
  }
}



//fileprivate func mergeVideo() {
//  let mixComposition : AVMutableComposition = AVMutableComposition()
//  var mutableCompositionVideoTrack : [AVMutableCompositionTrack] = []
//  var mutableCompositionAudioTrack : [AVMutableCompositionTrack] = []
//  let totalVideoCompositionInstruction : AVMutableVideoCompositionInstruction = AVMutableVideoCompositionInstruction()
//  
//  
//  //start merge
//  let aVideoAsset : AVAsset = AVAsset(url: tempRecordVideoURL())
//  let aAudioAsset : AVAsset = AVAsset(url: self.sourceAudioFileURL!)
//  
//  mutableCompositionVideoTrack.append(mixComposition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: kCMPersistentTrackID_Invalid)!)
//  mutableCompositionAudioTrack.append( mixComposition.addMutableTrack(withMediaType: AVMediaType.audio, preferredTrackID: kCMPersistentTrackID_Invalid)!)
//  
//  let aVideoAssetTrack : AVAssetTrack = aVideoAsset.tracks[0]
//  let aAudioAssetTrack : AVAssetTrack = aAudioAsset.tracks[0]
//  
//  do{
//    try mutableCompositionVideoTrack[0].insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: aVideoAssetTrack.timeRange.duration), of: aVideoAssetTrack, at: CMTime.zero)
//    
//    //In my case my audio file is longer then video file so i took videoAsset duration
//    //instead of audioAsset duration
//    
//    try mutableCompositionAudioTrack[0].insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: aVideoAssetTrack.timeRange.duration), of: aAudioAssetTrack, at: CMTime.zero)
//    
//    //Use this instead above line if your audiofile and video file's playing durations are same
//    
//    //            try mutableCompositionAudioTrack[0].insertTimeRange(CMTimeRangeMake(kCMTimeZero, aVideoAssetTrack.timeRange.duration), ofTrack: aAudioAssetTrack, atTime: kCMTimeZero)
//    
//  }catch{
//    
//  }
//  
//  totalVideoCompositionInstruction.timeRange = CMTimeRangeMake(start: CMTime.zero,duration: aVideoAssetTrack.timeRange.duration )
//  
//  let mutableVideoComposition : AVMutableVideoComposition = AVMutableVideoComposition()
//  mutableVideoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
//  
//  mutableVideoComposition.renderSize = CGSize(width: 720, height: 1280)
//  
//  //        playerItem = AVPlayerItem(asset: mixComposition)
//  //        player = AVPlayer(playerItem: playerItem!)
//  //
//  //
//  //        AVPlayerVC.player = player
//  
//  
//  
//  //find your video on this URl
//  let savePathUrl : NSURL = NSURL(fileURLWithPath: NSHomeDirectory() + "/Documents/newVideo.mp4")
//  
//  let assetExport: AVAssetExportSession = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality)!
//  assetExport.outputFileType = AVFileType.mp4
//  assetExport.outputURL = recordedVideoURL()
//  assetExport.shouldOptimizeForNetworkUse = true
//  
//  assetExport.exportAsynchronously { () -> Void in
//    switch assetExport.status {
//      
//    case AVAssetExportSession.Status.completed:
//      
//      //Uncomment this if u want to store your video in asset
//      
//      //let assetsLib = ALAssetsLibrary()
//      //assetsLib.writeVideoAtPathToSavedPhotosAlbum(savePathUrl, completionBlock: nil)
//      
//      print("success")
//    case  AVAssetExportSession.Status.failed:
//      print("failed \(assetExport.error)")
//    case AVAssetExportSession.Status.cancelled:
//      print("cancelled \(assetExport.error)")
//    default:
//      print("complete")
//    }
//  }
//}



//func processAudioData(audioData: UnsafePointer<AudioBufferList>, audioFormat inputFormat: CMFormatDescription, timingInfo: CMSampleTimingInfo, framesNumber: UInt32, mono: Bool) -> CMSampleBuffer? {
//  var sbuf : CMSampleBuffer?
//  var status : OSStatus?
//  var format: CMFormatDescription?
//
//  let audioFormat = CMAudioFormatDescriptionGetStreamBasicDescription(inputFormat)
//  var timing = timingInfo
//
//  var acl = AudioChannelLayout();
//  bzero(&acl, MemoryLayout<AudioChannelLayout>.size);
//  acl.mChannelLayoutTag = mono ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo;
//
//  status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: audioFormat!, layoutSize: MemoryLayout<AudioChannelLayout>.size, layout: &acl, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
//  if status != noErr {
//    print("Error CMAudioFormatDescriptionCreater :\(String(describing: status?.description))")
//    return nil
//  }
//
//  status = CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil, formatDescription: format, sampleCount: CMItemCount(framesNumber), sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sbuf)
//  if status != noErr {
//    print("Error CMSampleBufferCreate :\(String(describing: status?.description))")
//    return nil
//  }
//
//  guard let buf = sbuf else { return nil}
//  status = CMSampleBufferSetDataBufferFromAudioBufferList(buf, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: audioData)
//  let audiobufferListRaw: AudioBufferList = audioData.pointee
//  if status != noErr {
//    print("Error cCMSampleBufferSetDataBufferFromAudioBufferList :\(String(describing: status?.description))")
//    return nil
//  }
//
//  return buf
//}
