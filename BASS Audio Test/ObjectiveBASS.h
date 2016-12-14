//
//  ObjectiveBASS.h
//  BASS Audio Test
//
//  Created by Alec Gorge on 10/20/16.
//  Copyright © 2016 Alec Gorge. All rights reserved.
//

#import <Foundation/Foundation.h>

#include "bass.h"
#include "bassmix.h"

@class ObjectiveBASS;

@protocol ObjectiveBASSDelegate <NSObject>

- (BOOL)BASSIsLastTrack:(ObjectiveBASS *)bass;
- (void)BASSLoadNextTrackURL:(ObjectiveBASS *)bass;

@end

@interface ObjectiveBASS : NSObject

#pragma mark - Lifecyle

- (void)start;

@property (nonatomic, weak) id<ObjectiveBASSDelegate> delegate;

#pragma mark - Currently Playing

@property (nonatomic, readonly) NSURL *currentlyPlayingURL;
@property (nonatomic, readonly) NSInteger currentlyPlayingIdentifier;

#pragma mark - Next Track

@property (nonatomic, readonly) BOOL hasNext;
@property (nonatomic, readonly) NSURL *nextURL;
@property (nonatomic, readonly) NSInteger nextIdentifier;

- (void)nextTrackChanged;
- (void)changeNextTrackToURL:(NSURL *)url withIdentifier:(NSInteger)identifier;

#pragma mark - Playback Controls

- (void)seekToPercent:(float)pct;

- (void)resume;
- (void)pause;
- (void)next;

- (void)playURL:(NSURL *)url withIdentifier:(NSInteger)identifier;

@end
