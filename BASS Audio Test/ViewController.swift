//
//  ViewController.swift
//  BASS Audio Test
//
//  Created by Alec Gorge on 10/20/16.
//  Copyright © 2016 Alec Gorge. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    var bass: ObjectiveBASS? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        bass = ObjectiveBASS()
        
        bass?.start()
    }

    @IBAction func uiSeek(_ sender: AnyObject) {
        bass?.seek(toPercent: 0.97)
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

