//
//  ViewController.swift
//  TestingJS
//
//  Created by Nguyen Tuan on 11/11/18.
//  Copyright © 2018 Nguyen Tuan. All rights reserved.
//

import UIKit

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
        button.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        button.widthAnchor.constraint(equalToConstant: 50).isActive = true
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        
        button.addTarget(self, action: #selector(doSomething), for: .touchUpInside)
      
      let secondButton = UIButton(type: .custom)
      secondButton.setTitle("Video", for: .normal)
      secondButton.setTitleColor(UIColor.green, for: .normal)
      secondButton.translatesAutoresizingMaskIntoConstraints = false
      
      view.addSubview(secondButton)
      secondButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
      secondButton.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 10).isActive = true
      secondButton.widthAnchor.constraint(equalToConstant: 50).isActive = true
      secondButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
      
      secondButton.addTarget(self, action: #selector(openVideoComposition), for: .touchUpInside)
    }

    @objc func doSomething() {
        provider.start()
        for i in 0..<30 {
            provider.test(number: i)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            print("+++++++++++ start new test after 4 seconds in main thread")
            for i in 0..<10 {
                self.provider.test(number: i)
            }
        }
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
            print("+++++++++++ start new test after 4 seconds in main background")
            for i in 10..<20 {
                self.provider.test(number: i)
            }
        }
    }
  
  @objc func openVideoComposition() {
    provider.stop()
  }
}

