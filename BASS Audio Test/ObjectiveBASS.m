//
//  ObjectiveBASS.m
//  BASS Audio Test
//
//  Created by Alec Gorge on 10/20/16.
//  Copyright © 2016 Alec Gorge. All rights reserved.
//

#import "ObjectiveBASS.h"

#define dbug NSLog

@interface ObjectiveBASS (){
    
@public
    HSTREAM mixerMaster;
    
    HSTREAM streams[2];
    NSUInteger activeStreamIdx;
    
    BOOL hasInactiveStreamBeenPreloaded;
    BOOL isInactiveStreamUsed;
}

@property (nonatomic) HSTREAM activeStream;
@property (nonatomic) HSTREAM inactiveStream;

- (void)mixInNextTrack;

@end

void CALLBACK StreamDownloadProc(const void *buffer,
                                 DWORD length,
                                 void *user) {
    if(length > 4 && strncmp(buffer, "HTTP", 4) == 0) {
        dbug(@"[bass][StreamDownloadProc] received %u bytes.", length);
        dbug(@"[bass][StreamDownloadProc] HTTP data: %@", [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding]);
    }
}

void CALLBACK MixerEndSyncProc(HSYNC handle,
                               DWORD channel,
                               DWORD data,
                               void *user) {
    ObjectiveBASS *self = (__bridge ObjectiveBASS *)user;
    [self mixInNextTrack];
}

@implementation ObjectiveBASS

- (void)toggleActiveStreamIdx {
    activeStreamIdx = activeStreamIdx == 1 ? 0 : 1;
}

- (HSTREAM)activeStream {
    return streams[activeStreamIdx];
}

- (void)setActiveStream:(HSTREAM)activeStream {
    streams[activeStreamIdx] = activeStream;
}

- (HSTREAM)inactiveStream {
    return streams[activeStreamIdx == 1 ? 0 : 1];
}

- (void)setInactiveStream:(HSTREAM)inactiveStream {
    streams[activeStreamIdx == 1 ? 0 : 1] = inactiveStream;
}

- (NSInteger)calculateNextIndex {
    if(_currentIndex + 1 >= self.urls.count) {
        return NSNotFound;
    }
    
    return _currentIndex + 1;
}

- (void)start {
    [self setupBASS];
    
    [self play];
}

- (void)setupBASS {
    BASS_Init(-1, 44100, 0, NULL, NULL);
    
    mixerMaster = BASS_Mixer_StreamCreate(44100, 2, BASS_MIXER_END);
    
    BASS_ChannelSetSync(mixerMaster, BASS_SYNC_END | BASS_SYNC_MIXTIME, 0, MixerEndSyncProc, (__bridge void *)(self));
    activeStreamIdx = 0;
}

- (void)teardownBASS {
    BASS_Free();
}

- (void)next {
    _currentIndex = _nextIndex;
    _nextIndex = [self calculateNextIndex];
    
    [self setupInactiveStreamWithNextIdx];
}

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

- (HSTREAM)streamForIndex:(NSInteger)idx {
    return BASS_StreamCreateURL([self.urls[idx] cStringUsingEncoding:NSUTF8StringEncoding],
                                0,
                                BASS_STREAM_DECODE | BASS_SAMPLE_FLOAT | BASS_STREAM_STATUS,
                                StreamDownloadProc,
                                (__bridge void *)(self));
}

- (void)stopAndPlayIndex:(NSInteger)idx {
    // TODO: optimize to use the inactive stream if idx is the next index
    assert(BASS_ChannelStop(mixerMaster));
    
    // not assert'd because sometimes it should fail (initial playback)
    BASS_Mixer_ChannelRemove(self.activeStream);
    BASS_Mixer_ChannelRemove(self.inactiveStream);
    
    activeStreamIdx = 0;
    _currentIndex = idx;
    _nextIndex = [self calculateNextIndex];
    
    self.activeStream = [self streamForIndex:idx];
    [self setupInactiveStreamWithNextIdx];
    
    assert(BASS_Mixer_StreamAddChannel(mixerMaster, self.activeStream, BASS_STREAM_AUTOFREE | BASS_MIXER_NORAMPIN));
    assert(BASS_ChannelPlay(mixerMaster, FALSE));
}

- (void)setupInactiveStreamWithNextIdx {
    if(self.nextIndex != NSNotFound) {
        dbug(@"[bass] Next index found. Setting up next stream.");
        BASS_Mixer_ChannelRemove(self.inactiveStream);
        
        self.inactiveStream = [self streamForIndex:self.nextIndex];
        isInactiveStreamUsed = YES;
        hasInactiveStreamBeenPreloaded = NO;
    }
    else {
        isInactiveStreamUsed = NO;
        hasInactiveStreamBeenPreloaded = NO;
    }
}

- (void)preloadNextTrack {
    dbug(@"[bass][preloadNextTrack] Preloading next track");
    BASS_ChannelUpdate(self.inactiveStream, 0);
    hasInactiveStreamBeenPreloaded = YES;
}

- (void)mixInNextTrack {
    dbug(@"[bass][MixerEndSyncProc] End Sync called for stream");
    
    HSTREAM previouslyInactiveStream = self.inactiveStream;
    
    if(isInactiveStreamUsed) {
        BASS_Mixer_StreamAddChannel(self->mixerMaster, previouslyInactiveStream, BASS_STREAM_AUTOFREE | BASS_MIXER_NORAMPIN);
        BASS_ChannelUpdate(previouslyInactiveStream, 0);
        
        BASS_ChannelSetPosition(self->mixerMaster, 0, BASS_POS_BYTE);
    }
    
    [self toggleActiveStreamIdx];
    
    [self next];
}

- (void)printStatus {
    [self printStatus:activeStreamIdx withTrackIndex:_currentIndex];
    [self printStatus:activeStreamIdx == 0 ? 1 : 0 withTrackIndex:_nextIndex];
}

- (void)printStatus:(NSInteger)streamIdx withTrackIndex:(NSInteger)idx {
    QWORD connected = BASS_StreamGetFilePosition(streams[streamIdx], BASS_FILEPOS_CONNECTED);
    QWORD downloadedBytes = BASS_StreamGetFilePosition(streams[streamIdx], BASS_FILEPOS_DOWNLOAD);
    QWORD totalBytes = BASS_StreamGetFilePosition(streams[streamIdx], BASS_FILEPOS_SIZE);
    
    QWORD playedBytes = BASS_ChannelGetPosition(streams[streamIdx], BASS_POS_BYTE);
    QWORD totalPlayableBytes = BASS_ChannelGetLength(streams[streamIdx], BASS_POS_BYTE);
    
    double downloadPct = 1.0 * downloadedBytes / totalBytes;
    double playPct = 1.0 * playedBytes / totalPlayableBytes;
    
    dbug(@"[Stream: %lu, track: %lu] Connected: %llu. Download progress: %.3f. Playback progress: %.3f.\n", (unsigned long)streamIdx, idx, connected, downloadPct, playPct);
    
    // not 1.0f because sometimes file sizes get a bit off
    if(streamIdx == activeStreamIdx && downloadPct >= .98f && !hasInactiveStreamBeenPreloaded) {
        dbug(@"[bass] Active stream fully downloaded. Preloading next.");
        [self preloadNextTrack];
    }
}

- (void)seekToPercent:(float)pct {
    QWORD len = BASS_ChannelGetLength(self.activeStream, BASS_POS_BYTE);
    double duration = BASS_ChannelBytes2Seconds(self.activeStream, len);
    QWORD seekTo = BASS_ChannelSeconds2Bytes(self.activeStream, duration * pct);
    double seekToDuration = BASS_ChannelBytes2Seconds(self.activeStream, seekTo);
    
    dbug(@"[bass][stream 1] Found length in bytes to be %llu bytes/%f. Seeking to: %llu bytes/%f", len, duration, seekTo, seekToDuration);
    
    assert(BASS_ChannelSetPosition(self.activeStream, seekTo, BASS_POS_BYTE));
}

@end
