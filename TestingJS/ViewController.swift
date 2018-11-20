//
//  ViewController.swift
//  TestingJS
//
//  Created by Nguyen Tuan on 11/11/18.
//  Copyright © 2018 Nguyen Tuan. All rights reserved.
//

import UIKit
import AVKit

class ViewController: UIViewController {
  let provider = JSDataProvider()
  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view, typically from a nib.
    let button = UIButton(type: .custom)
    button.setTitle("Test", for: .normal)
    button.setTitleColor(UIColor.black, for: .normal)
    button.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(button)
    button.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
    button.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50).isActive = true
    button.widthAnchor.constraint(equalToConstant: 50).isActive = true
    button.heightAnchor.constraint(equalToConstant: 50).isActive = true
    
    button.addTarget(self, action: #selector(doSomething), for: .touchUpInside)
    
    let secondButton = UIButton(type: .custom)
    secondButton.setTitle("Load", for: .normal)
    secondButton.setTitleColor(UIColor.black, for: .normal)
    secondButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(secondButton)
    secondButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
    secondButton.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 10).isActive = true
    secondButton.widthAnchor.constraint(equalToConstant: 50).isActive = true
    secondButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
    secondButton.addTarget(self, action: #selector(load), for: .touchUpInside)
    
    let thirdButton = UIButton(type: .custom)
    thirdButton.setTitle("Load Compiled", for: .normal)
    thirdButton.setTitleColor(UIColor.black, for: .normal)
    thirdButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(thirdButton)
    thirdButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
    thirdButton.topAnchor.constraint(equalTo: secondButton.bottomAnchor, constant: 10).isActive = true
    thirdButton.widthAnchor.constraint(equalToConstant: 150).isActive = true
    thirdButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
    thirdButton.addTarget(self, action: #selector(loadCompiled), for: .touchUpInside)
    
    let fourthButton = UIButton(type: .custom)
    fourthButton.setTitle("Execute", for: .normal)
    fourthButton.setTitleColor(UIColor.black, for: .normal)
    fourthButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(fourthButton)
    fourthButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
    fourthButton.topAnchor.constraint(equalTo: thirdButton.bottomAnchor, constant: 10).isActive = true
    fourthButton.widthAnchor.constraint(equalToConstant: 100).isActive = true
    fourthButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
    fourthButton.addTarget(self, action: #selector(execute), for: .touchUpInside)
    
    let fifthButton = UIButton(type: .custom)
    fifthButton.setTitle("Stop", for: .normal)
    fifthButton.setTitleColor(UIColor.green, for: .normal)
    fifthButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(fifthButton)
    fifthButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
    fifthButton.topAnchor.constraint(equalTo: fourthButton.bottomAnchor, constant: 10).isActive = true
    fifthButton.widthAnchor.constraint(equalToConstant: 50).isActive = true
    fifthButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
    fifthButton.addTarget(self, action: #selector(stop), for: .touchUpInside)
    
    let cameraButton = UIButton(type: .custom)
    cameraButton.setTitle("Camera", for: .normal)
    cameraButton.setTitleColor(UIColor.blue, for: .normal)
    cameraButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(cameraButton)
    cameraButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
    cameraButton.topAnchor.constraint(equalTo: fifthButton.bottomAnchor, constant: 10).isActive = true
    cameraButton.widthAnchor.constraint(equalToConstant: 75).isActive = true
    cameraButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
    cameraButton.addTarget(self, action: #selector(ViewController.camera), for: .touchUpInside)
    
    let playButton = UIButton(type: .custom)
    playButton.setTitle("Play", for: .normal)
    playButton.setTitleColor(UIColor.blue, for: .normal)
    playButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(playButton)
    playButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
    playButton.topAnchor.constraint(equalTo: cameraButton.bottomAnchor, constant: 10).isActive = true
    playButton.widthAnchor.constraint(equalToConstant: 75).isActive = true
    playButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
    playButton.addTarget(self, action: #selector(ViewController.play), for: .touchUpInside)
  }
  
  @objc func camera() {
    let vc = SWRecordVideoViewController()
    present(vc, animated: true, completion: nil)
  }
  
  @objc func doSomething() {
    provider.start()
  }
  
  @objc func stop() {
    provider.stop()
  }
  
  @objc func execute() {
    provider.execute(script: "getData()")
  }
  
  @objc func loadCompiled() {
    let bundle = Bundle.main.url(forResource: "data-compiled", withExtension: "js")
    provider.load(jsBundle: bundle!)
  }
  
  @objc func load() {
    let bundle = Bundle.main.url(forResource: "data", withExtension: "js")
    provider.load(jsBundle: bundle!)
  }
  
  @objc func play() {
    let tempDir = NSTemporaryDirectory()
    let tempDirURL = URL(fileURLWithPath: tempDir)
    let videoURL = tempDirURL.appendingPathComponent("recordedVideo")
    let playbackViewController = AVPlayerViewController()
    playbackViewController.player = AVPlayer(url: videoURL)
    present(playbackViewController, animated: true) {
      playbackViewController.player?.play()
    }
  }
}

