//
//  JSDataProvider.swift
//  TestingJS
//
//  Created by Nguyen Tuan on 11/11/18.
//  Copyright © 2018 Nguyen Tuan. All rights reserved.
//

import UIKit
import JavaScriptCore

final class JSDataProvider {
  private typealias Job = ()->()
  private var thread: Thread?
  
  private var queue: [RunloopSource.RunloopSourceContext] = []
  
  public init() {
  }
  
  public func start() {
    if thread == nil {
      let workingThread = Thread(target: self, selector: #selector(JSDataProvider.main), object: nil)
      workingThread.qualityOfService = .utility
      thread = workingThread
      
      thread?.start()
    }
  }
  
  public func stop() {
    thread?.cancel()
    thread = nil
    
    if queue.count > 0 {
      let sourceInfo = queue[0]
      sourceInfo.source.stop(runloop: sourceInfo.runloop)
    }
  }
  
  private func execute(_ job: @escaping Job) throws {
  }
  
  private var pendingTask = [Int]()
  public func test(number: Int) {
    guard queue.count > 0 else {
      return
    }
    let sourceInfo = queue[0]
    sourceInfo.source.addCommand(number)
    sourceInfo.source.fireCommandsOnRunLoop(runloop: sourceInfo.runloop)
  }
  
  fileprivate func registerSource(sourceInfo: RunloopSource.RunloopSourceContext) {
    queue.append(sourceInfo)
  }
  
  fileprivate func removeSource(sourceInfo: RunloopSource.RunloopSourceContext) {
    if let index = queue.firstIndex(where: {$0.source === sourceInfo.source}) {
      queue.remove(at: index)
    }
  }
  
  //MARK: - main
  @objc private func main() {
    var done = false
    //        var virtualMachine = JSVirtualMachine()
    var customRunloop: RunloopSource? = RunloopSource(provider: self)
    customRunloop?.addToCurrentRunloop()
    
    while !done {
      let result = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 10, true)
      if result == .stopped {
        done = true
      }
    }
    
    //release resource
    customRunloop = nil
  }
}

private class RunloopSource: NSObject {
  final class RunloopSourceContext: NSObject {
    let runloop: CFRunLoop
    let source: RunloopSource
    
    init(runloop: CFRunLoop, source: RunloopSource) {
      self.runloop = runloop
      self.source = source
      
      super.init()
    }
    
    deinit {
      CFRunLoopStop(runloop)
    }
  }
  
  private let commandQueue = DispatchQueue(label: "runloopSourceCommandQueue")
  private let commandQueueKey = DispatchSpecificKey<Void>()
  private var data: [Any] = []
  public func addCommand(_ command: Any) {
    if DispatchQueue.getSpecific(key: commandQueueKey) == nil {
      commandQueue.async { [weak self] in
        self?.data.append(command)
      }
    } else {
      data.append(command)
    }
  }
  
  private func poll() -> Any? {
    var result: Any? = nil
    if DispatchQueue.getSpecific(key: commandQueueKey) == nil {
      commandQueue.sync { [weak self] in
        guard let this = self else { return }
        if this.data.count > 0 {
          result = this.data.removeFirst()
        }
      }
    } else {
      result = data.removeFirst()
    }
    return result
  }
  
  weak var provider: JSDataProvider?
  var runloopSource: CFRunLoopSource!
  init(provider: JSDataProvider) {
    self.provider = provider
    super.init()
    self.setup()
  }
  
  deinit {
    runloopSource = nil
  }
  
  private func setup() {
    let pointer = bridgeUnRetained(obj: self)
    var context = CFRunLoopSourceContext(version: 0,
                                         info: pointer,
                                         retain: nil,
                                         release: nil,
                                         copyDescription: nil,
                                         equal: nil,
                                         hash: nil,
                                         schedule: { (info, rl, mode) in
                                          let inputSource: RunloopSource = bridgeTransfer(ptr: info!)
                                          let inputContext = RunloopSourceContext(runloop: rl!, source: inputSource)
                                          DispatchQueue.main.async {
                                            inputSource.provider?.registerSource(sourceInfo: inputContext)
                                          }
    },
                                         cancel: { (info, rl, mode) in
                                          let inputSource: RunloopSource = bridgeTransfer(ptr: info!)
                                          let inputContext = RunloopSourceContext(runloop: rl!, source: inputSource)
                                          DispatchQueue.main.async {
                                            inputSource.provider?.removeSource(sourceInfo: inputContext)
                                          }
                                          
    }) { (info) in
      let inputSource: RunloopSource = bridgeTransfer(ptr: info!)
      inputSource.sourceFired()
    }
    
    runloopSource = CFRunLoopSourceCreate(nil, 0, &context)
    commandQueue.setSpecific(key: commandQueueKey, value: ())
  }
  
  func addToCurrentRunloop() {
    let runloop = CFRunLoopGetCurrent()
    CFRunLoopAddSource(runloop!, runloopSource, CFRunLoopMode.defaultMode)
  }
  
  func fireCommandsOnRunLoop(runloop: CFRunLoop) {
    CFRunLoopSourceSignal(runloopSource)
    CFRunLoopWakeUp(runloop)
  }
  
  func stop(runloop: CFRunLoop) {
    CFRunLoopSourceInvalidate(runloopSource)
    CFRunLoopRemoveSource(runloop, runloopSource, CFRunLoopMode.defaultMode)
    CFRunLoopStop(runloop)
  }
  
  func sourceFired() {
    if let command = poll() {
      executeCommand(command: command)
      
      //after finish the job, try to poll next command
      CFRunLoopSourceSignal(runloopSource)
    }
  }
  
  func executeCommand(command: Any) {
    print("start working on thread: \(Thread.current) with data: \(String(describing: command))")
  }
}

func bridgeTransfer<T : AnyObject>(ptr : UnsafeRawPointer) -> T {
    return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
}

func bridgeUnRetained<T : AnyObject>(obj : T) -> UnsafeMutableRawPointer {
    return Unmanaged.passUnretained(obj).toOpaque()
}
