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
    
    let urls = ["http://phish.in/audio/000/025/507/25507.mp3",
                "http://phish.in/audio/000/025/508/25508.mp3",
                "http://phish.in/audio/000/025/509/25509.mp3",
                "http://phish.in/audio/000/025/510/25510.mp3"]
    
    var idx = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        bass = ObjectiveBASS()
        
        bass?.delegate = self
        bass?.dataSource = self
        
        bass?.play(URL(string: urls[idx])!, withIdentifier: 100)
        
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { (t) in
            if let b = self.bass {
                self.uiLabelElapsed.text = self.stringFromTimeInterval(b.elapsed)
                self.uiLabelDuration.text = self.stringFromTimeInterval(b.currentDuration)
            }
        }
    }
    
    func stringFromTimeInterval(_ interval: TimeInterval) -> String {
        let ti = NSInteger(interval)
        
        let ms = Int((interval.truncatingRemainder(dividingBy: 1)) * 1000)
        
        let seconds = ti % 60
        let minutes = (ti / 60) % 60
        
        return NSString(format: "%0.2d:%0.2d.%0.3d", minutes,seconds,ms) as String
    }

    /*
 - (void)play {
 self.urls = @[
 @"http://phish.in/audio/000/025/507/25507.mp3",
 @"http://phish.in/audio/000/025/508/25508.mp3",
 @"http://phish.in/audio/000/025/509/25509.mp3",
 @"http://phish.in/audio/000/025/510/25510.mp3"
 ];
 
 [self stopAndPlayIndex:0];
 
 [NSTimer scheduledTimerWithTimeInterval:0.5
 target:self
 selector:@selector(printStatus)
 userInfo:nil
 repeats:YES];
 }
 */
 
    @IBOutlet weak var uiLabelElapsed: UILabel!
    @IBOutlet weak var uiLabelDuration: UILabel!
    
    @IBAction func uiSeek(_ sender: AnyObject) {
        bass?.seek(toPercent: 0.97)
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

extension ViewController : ObjectiveBASSDelegate {
    func bassDownloadProgressChanged(_ forActiveTrack: Bool, downloadedBytes: UInt64, totalBytes: UInt64) {
        
    }
    
    func bassDownloadPlaybackStateChanged(_ state: BassPlaybackState) {
        
    }
    
    func bassErrorStartingStream(_ error: Error, for url: URL, withIdentifier identifier: Int) {
        print(error);
    }
}

extension ViewController : ObjectiveBASSDataSource {
    func identifierToIdx(_ ident: Int) -> Int {
        return ident - 100
    }
    
    func indexToIdentifier(_ idx: Int) -> Int {
        return idx + 100
    }
    
    func bassisPlayingLastTrack(_ bass: ObjectiveBASS, with url: URL, andIdentifier identifier: Int) -> Bool {
        return identifierToIdx(identifier) == urls.count - 1
    }
    
    func bassNextTrackIdentifier(_ bass: ObjectiveBASS, after url: URL, withIdentifier identifier: Int) -> Int {
        return identifierToIdx(indexToIdentifier(identifier) + 1)
    }
    
    func bassLoadNextTrackURL(_ bass: ObjectiveBASS, forIdentifier identifier: Int) {
        bass.nextTrackURLLoaded(URL(string: urls[identifierToIdx(identifier)])!)
    }
}

