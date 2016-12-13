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

@interface ObjectiveBASS : NSObject

- (void)start;

@property (nonatomic) NSArray<NSString *> *urls;
@property (nonatomic, readonly) NSInteger currentIndex;
@property (nonatomic, readonly) NSInteger nextIndex;

- (void)seekToPercent:(float)pct;

@end
