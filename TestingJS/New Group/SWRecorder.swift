//
//  SWRecorder.swift
//  TestingJS
//
//  Created by Anh Tuan Nguyen on 20/11/18.
//  Copyright © 2018 Nguyen Tuan. All rights reserved.
//

import AVFoundation

protocol SWRecorderOutput: class {
  func recorderReadyForCollection()
  func recorderDidFinish(withFile fileUrl: URL)
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
  let writingVideoSpecificKey = DispatchSpecificKey<String>()
  weak var output: SWRecorderOutput?
  var isRunning = false
  var minimumDurationAllowed = 5.0
  var maximumDurationAllowed = 60.0
  
  override init() {
    super.init()

    writingVideoQueue.setSpecific(key: writingVideoSpecificKey, value: self.description)
  }
  
  private func executeWritingVideoJob(_ job: @escaping ()->()) {
    if DispatchQueue.getSpecific(key: writingVideoSpecificKey) == self.description {
      job()
    } else {
      writingVideoQueue.async {
        job()
      }
    }
  }
  
  // Writer
  fileprivate var assetWriter: AVAssetWriter?
  fileprivate var videoWriterInput: AVAssetWriterInput?
  fileprivate var audioWriterInput: AVAssetWriterInput?
  fileprivate var workingFileURL: URL = tempRecordVideoURL()
  func prepare() throws {
    guard assetWriter == nil, !isRunning else {
      throw SWRecorderError.otherWritterIsRunning
    }
    
    //first reset all variables
    reset()
    
    //we only allow 1 record 1 video at a time
    
    do {
      try? FileManager.default.removeItem(at: workingFileURL)
      let writer = try AVAssetWriter(outputURL: workingFileURL, fileType: .mov)
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
  
  // Multiple shoot support
  private class SaveStateTimingInfo {
    var begin: CMTime
    var last: CMTime?
    var oldDiff: CMTime?
    var diff: CMTime?
    var pause: CMTime?
    
    init(beginTime time: CMTime) {
      begin = time
    }
    
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
    
    func predictDuration(currentTime time: CMTime) -> CMTime {
      return time - begin - (diff ?? CMTime.zero)
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
      if let predictDuration = this.videoLastTimingInfo?.predictDuration(currentTime: bufferTimestamp) {
        if CMTimeGetSeconds(predictDuration) > this.minimumDurationAllowed {
          this.output?.recorderReadyForCollection()
        } else if CMTimeGetSeconds(predictDuration) > this.maximumDurationAllowed {
          this.finish()
          return
        }
      }
      if this.assetWriter?.status == .unknown {
        this.assetWriter?.startWriting()
        this.assetWriter?.startSession(atSourceTime: bufferTimestamp)
        //create last info for video and audio buffer
        this.videoLastTimingInfo = SaveStateTimingInfo(beginTime: bufferTimestamp)
        this.audioLastTimingInfo = SaveStateTimingInfo(beginTime: bufferTimestamp)
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
    DispatchQueue.main.async {
      self.output?.recorderDidFinish(withFile: self.workingFileURL)
    }
  }
  
}
