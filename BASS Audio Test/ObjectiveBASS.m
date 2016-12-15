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
    
@private
    HSTREAM mixerMaster;
    
    HSTREAM streams[2];
    NSUInteger activeStreamIdx;
    
    BOOL hasInactiveStreamPreloadStarted;
    BOOL hasInactiveStreamPreloadFinished;
    BOOL isInactiveStreamUsed;
    
    BOOL hasActiveStreamPreloadStarted;
    BOOL hasActiveStreamPreloadFinished;

    dispatch_queue_t queue;
    
    BassPlaybackState _currentState;
}

@property (nonatomic) HSTREAM activeStream;
@property (nonatomic) HSTREAM inactiveStream;

- (void)mixInNextTrack:(HSTREAM)completedStream;
- (void)streamDownloadComplete:(HSTREAM)stream;

- (void)streamStalled:(HSTREAM)stream;
- (void)streamResumedAfterStall:(HSTREAM)stream;

@end

/*
void CALLBACK StreamDownloadProc(const void *buffer,
                                 DWORD length,
                                 void *user) {
    if(length > 4 && strncmp(buffer, "HTTP", 4) == 0) {
        dbug(@"[bass][StreamDownloadProc] received %u bytes.", length);
        dbug(@"[bass][StreamDownloadProc] HTTP data: %@", [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding]);
    }
}
*/

void CALLBACK MixerEndSyncProc(HSYNC handle,
                               DWORD channel,
                               DWORD data,
                               void *user) {
    ObjectiveBASS *self = (__bridge ObjectiveBASS *)user;
    [self mixInNextTrack:channel];
}

void CALLBACK StreamDownloadCompleteSyncProc(HSYNC handle,
                                             DWORD channel,
                                             DWORD data,
                                             void *user) {
    // channel is the HSTREAM we created before
    dbug(@"[bass][stream] stream download completed: handle: %u. channel: %u", handle, channel);
    ObjectiveBASS *self = (__bridge ObjectiveBASS *)user;
    [self streamDownloadComplete:channel];
}

void CALLBACK StreamStallSyncProc(HSYNC handle,
                                  DWORD channel,
                                  DWORD data,
                                  void *user) {
    // channel is the HSTREAM we created before
    dbug(@"[bass][stream] stream stall: handle: %u. channel: %u", handle, channel);
    ObjectiveBASS *self = (__bridge ObjectiveBASS *)user;
    
    if(data == 0 /* stalled */) {
        [self streamStalled:channel];
    }
    else if(data == 1 /* resumed */) {
        [self streamResumedAfterStall:channel];
    }
}

@implementation ObjectiveBASS

- (void)stopAndResetInactiveStream {
    // no assert because this might fail
    BASS_ChannelStop(self.inactiveStream);
    
    _nextURL = 0;
    _nextIdentifier = NSNotFound;
    isInactiveStreamUsed = NO;
    hasInactiveStreamPreloadStarted = NO;
    hasInactiveStreamPreloadFinished = NO;
}

- (void)nextTrackChanged {
    if ([self.dataSource BASSIsPlayingLastTrack:self
                                        withURL:self.currentlyPlayingURL
                                  andIdentifier:self.currentlyPlayingIdentifier]) {
        [self stopAndResetInactiveStream];
    }
    else {
        _nextIdentifier = [self.dataSource BASSNextTrackIdentifier:self
                                                          afterURL:self.currentlyPlayingURL
                                                    withIdentifier:self.currentlyPlayingIdentifier];
        
        [self.dataSource BASSLoadNextTrackURL:self
                                forIdentifier:self.nextIdentifier];
    }
}

- (void)nextTrackURLLoaded:(NSURL *)url {
    dispatch_async(queue, ^{
        [self _nextTrackURLLoaded:url];
    });
}

- (void)_nextTrackURLLoaded:(NSURL *)url {
    if(isInactiveStreamUsed) {
        BASS_ChannelStop(self.inactiveStream);
    }
    
    _nextURL = url;
    
    if(hasActiveStreamPreloadFinished) {
        [self setupInactiveStreamWithNext];
    }
}

- (BOOL)hasNextTrackChanged {
    BOOL isPlayingLast = [self.dataSource BASSIsPlayingLastTrack:self
                                                         withURL:self.currentlyPlayingURL
                                                   andIdentifier:self.currentlyPlayingIdentifier];
    
    if(!self.hasNextURL && !isPlayingLast) {
        return YES;
    }
    else if(self.hasNextURL && isPlayingLast) {
        return YES;
    }
    else if(self.hasNextURL && self.nextIdentifier != [self.dataSource BASSNextTrackIdentifier:self
                                                                                      afterURL:self.currentlyPlayingURL
                                                                                withIdentifier:self.currentlyPlayingIdentifier]) {
        return YES;
    }
    
    return NO;
}

- (BOOL)updateNextTrackIfNecessary {
    if([self hasNextTrackChanged]) {
        [self nextTrackChanged];
        return YES;
    }
    
    return NO;
}

#pragma mark - Active/Inactive Stream Managment

- (void)toggleActiveStream {
    activeStreamIdx = activeStreamIdx == 1 ? 0 : 1;
    
    hasActiveStreamPreloadStarted = hasInactiveStreamPreloadStarted;
    hasActiveStreamPreloadFinished = hasInactiveStreamPreloadFinished;
    
    _currentlyPlayingURL = self.nextURL;
    _currentlyPlayingIdentifier = self.nextIdentifier;
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

#pragma mark - Order Management

- (BOOL)hasNextURL {
    return _nextURL != nil;
}

#pragma mark - BASS Lifecycle

- (instancetype)init {
    if (self = [super init]) {
        queue = dispatch_queue_create("com.alecgorge.ios.objectivebass", NULL);
        [self setupBASS];
    }
    return self;
}

- (void)dealloc {
    [self teardownBASS];
}

- (void)setupBASS {
    dispatch_async(queue, ^{
        // BASS_SetConfigPtr(BASS_CONFIG_NET_PROXY, "192.168.1.196:8888");
        BASS_SetConfig(BASS_CONFIG_NET_TIMEOUT, 15 * 1000);
        
        BASS_Init(-1, 44100, 0, NULL, NULL);
        
        mixerMaster = BASS_Mixer_StreamCreate(44100, 2, BASS_MIXER_END);
        
        BASS_ChannelSetSync(mixerMaster, BASS_SYNC_END | BASS_SYNC_MIXTIME, 0, MixerEndSyncProc, (__bridge void *)(self));
        
        activeStreamIdx = 0;
    });
}

- (void)teardownBASS {
    BASS_Free();
}

- (HSTREAM)buildStreamForURL:(NSURL *)url
                  withOffset:(DWORD)offset
               andIdentifier:(NSInteger)identifier {
    HSTREAM newStream = BASS_StreamCreateURL([url.absoluteString cStringUsingEncoding:NSUTF8StringEncoding],
                                             offset,
                                             BASS_STREAM_DECODE | BASS_SAMPLE_FLOAT | BASS_STREAM_STATUS,
                                             NULL, // StreamDownloadProc,
                                             NULL); // (__bridge void *)(self));
    
    // oops
    if(newStream == 0) {
        NSError *err = [self errorForErrorCode:BASS_ErrorGetCode()];
        
        dbug(@"[bass][stream] error creating new stream: %ld %@", (long)err.code, err.localizedDescription);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate BASSErrorStartingStream:err
                                            forURL:url
                                    withIdentifier:identifier];
        });
        
        return 0;
    }
    
    assert(BASS_ChannelSetSync(newStream,
                               BASS_SYNC_MIXTIME | BASS_SYNC_DOWNLOAD,
                               0,
                               StreamDownloadCompleteSyncProc,
                               (__bridge void *)(self)));
    
    assert(BASS_ChannelSetSync(newStream,
                               BASS_SYNC_MIXTIME | BASS_SYNC_STALL,
                               0,
                               StreamStallSyncProc,
                               (__bridge void *)(self)));
    
    dbug(@"[bass][stream] created new stream: %u", newStream);
    
    return newStream;
}

- (HSTREAM)buildAndSetupActiveStreamForURL:(NSURL *)url
                            withIdentifier:(NSInteger)ident {
    return [self buildAndSetupActiveStreamForURL:url
                                  withIdentifier:ident
                                       andOffset:0];
}

- (HSTREAM)buildAndSetupActiveStreamForURL:(NSURL *)url
                            withIdentifier:(NSInteger)ident
                                 andOffset:(DWORD)offset {
    HSTREAM newStream = [self buildStreamForURL:url
                                     withOffset:offset
                                  andIdentifier:ident];
    
    if(newStream == 0) {
        return 0;
    }
    
    self.activeStream = newStream;
    
    _currentlyPlayingURL = url;
    _currentlyPlayingIdentifier = ident;
    
    hasActiveStreamPreloadStarted = YES;
    hasActiveStreamPreloadFinished = NO;
    
    return self.activeStream;
}

- (HSTREAM)buildAndSetupInactiveStreamForURL:(NSURL *)url
                              withIdentifier:(NSInteger)ident {
    HSTREAM newStream = [self buildStreamForURL:url withOffset:0 andIdentifier:ident];
    
    if(newStream == 0) {
        return 0;
    }
    
    self.inactiveStream = newStream;
    
    _nextURL = url;
    _nextIdentifier = ident;
    
    isInactiveStreamUsed = YES;
    hasInactiveStreamPreloadStarted = YES;
    hasActiveStreamPreloadFinished = NO;
    
    return self.inactiveStream;
}

- (void)playURL:(NSURL *)url withIdentifier:(NSInteger)identifier {
    [self playURL:url
   withIdentifier:identifier
       startingAt:0.0f];
}

- (void)playURL:(NSURL *)url
 withIdentifier:(NSInteger)identifier
     startingAt:(float)pct {
    if(self.currentlyPlayingURL != nil && self.hasNextURL && [url isEqual:self.nextURL]) {
        _nextIdentifier = identifier;
        [self next];
        return;
    }
    
    dispatch_async(queue, ^{
        // stop playback
        assert(BASS_ChannelStop(mixerMaster));
        
        // stop channels to allow them to be freed
        BASS_ChannelStop(self.activeStream);
        
        // remove this stream from the mixer
        // not assert'd because sometimes it should fail (initial playback)
        BASS_Mixer_ChannelRemove(self.activeStream);
        
        // do the same thing for inactive--but only if the next track is actually different
        // and if something is currently playing
        if(self.currentlyPlayingURL != nil && [self hasNextTrackChanged]) {
            BASS_ChannelStop(self.inactiveStream);
            BASS_Mixer_ChannelRemove(self.inactiveStream);
        }
        
        if([self buildAndSetupActiveStreamForURL:url
                                  withIdentifier:identifier] != 0) {
            assert(BASS_Mixer_StreamAddChannel(mixerMaster,
                                               self.activeStream,
                                               BASS_STREAM_AUTOFREE | BASS_MIXER_NORAMPIN));
            assert(BASS_ChannelPlay(mixerMaster, FALSE));
            
            [self changeCurrentState:BassPlaybackStatePlaying];
        }
    });    
}

- (void)streamStalled:(HSTREAM)stream {
    if(stream == self.activeStream) {
        [self changeCurrentState:BassPlaybackStateStalled];
    }
}

- (void)streamResumedAfterStall:(HSTREAM)stream {
    if(stream == self.activeStream) {
        [self changeCurrentState:BassPlaybackStatePlaying];
    }
}

- (void)streamDownloadComplete:(HSTREAM)stream {
    if(stream == self.activeStream) {
        if(!hasActiveStreamPreloadFinished) {
            hasActiveStreamPreloadFinished = YES;
            
            // active stream has fully loaded, load the next one
            if(![self updateNextTrackIfNecessary]) {
                [self setupInactiveStreamWithNext];
            }
        }
    }
    else if(stream == self.inactiveStream) {
        hasInactiveStreamPreloadStarted = YES;
        hasInactiveStreamPreloadFinished = YES;
        
        // the inactive stream is also loaded--good, but we don't want to load anything else
        // we do want to start decoding the downloaded data though
        
        // The amount of data to render, in milliseconds... 0 = default (2 x update period)
        // assert(BASS_ChannelUpdate(self.inactiveStream, 0));
    }
    else {
        assert(FALSE);
    }
}

- (void)setupInactiveStreamWithNext {
    if(self.hasNextURL) {
        dbug(@"[bass] Next index found. Setting up next stream.");
        BASS_Mixer_ChannelRemove(self.inactiveStream);
        
        if([self buildAndSetupInactiveStreamForURL:self.nextURL
                                    withIdentifier:self.nextIdentifier] != 0) {
            [self startPreloadingInactiveStream];
        }
    }
    else {
        isInactiveStreamUsed = NO;
        hasInactiveStreamPreloadStarted = NO;
        hasInactiveStreamPreloadFinished = NO;
    }
}

- (void)startPreloadingInactiveStream {
    // don't start loading anything until the active stream has finished
    if(!hasActiveStreamPreloadFinished) {
        return;
    }

    dbug(@"[bass][preloadNextTrack] Preloading next track");
    BASS_ChannelUpdate(self.inactiveStream, 0);
    hasInactiveStreamPreloadStarted = YES;
}

- (void)mixInNextTrack:(HSTREAM)completedTrack {
    dbug(@"[bass][MixerEndSyncProc] End Sync called for stream: %u", completedTrack);
    
    if(completedTrack != self.activeStream && completedTrack != mixerMaster) {
        dbug(@"[bass][MixerEndSyncProc] completed stream is no longer active: %u", completedTrack);
        return;
    }
    
    HSTREAM previouslyInactiveStream = self.inactiveStream;
    
    if([self updateNextTrackIfNecessary]) {
        // track updated, do nothing
        return;
    }
    
    if(isInactiveStreamUsed) {
        assert(BASS_Mixer_StreamAddChannel(mixerMaster,
                                           previouslyInactiveStream,
                                           BASS_STREAM_AUTOFREE | BASS_MIXER_NORAMPIN));
        assert(BASS_ChannelSetPosition(mixerMaster, 0, BASS_POS_BYTE));
        
        // now previousInactiveStream == self.activeStream
        [self toggleActiveStream];

        [self stopAndResetInactiveStream];
        
        // don't set up next here, wait until current is downloaded
        // the new current might have already finished though #wifi
        //
        // in that case, retrigger the download complete event since it was last called
        // when the currently active stream was inactive and it did nothing
        if(hasActiveStreamPreloadFinished) {
            if(![self updateNextTrackIfNecessary]) {
                [self setupInactiveStreamWithNext];
            }
        }
    }
    else {
        // no inactive stream. nothing to do...
        // move into a paused state
        BASS_ChannelPause(mixerMaster);
        [self changeCurrentState:BassPlaybackStatePaused];
    }
}

- (void)printStatus {
    [self printStatus:activeStreamIdx withTrackIndex:self.currentlyPlayingIdentifier];
    [self printStatus:activeStreamIdx == 0 ? 1 : 0 withTrackIndex:self.nextIdentifier];
    dbug(@" ");
}

- (void)printStatus:(NSInteger)streamIdx withTrackIndex:(NSInteger)idx {
    QWORD connected = BASS_StreamGetFilePosition(streams[streamIdx], BASS_FILEPOS_CONNECTED);
    QWORD downloadedBytes = BASS_StreamGetFilePosition(streams[streamIdx], BASS_FILEPOS_DOWNLOAD);
    QWORD totalBytes = BASS_StreamGetFilePosition(streams[streamIdx], BASS_FILEPOS_SIZE);
    
    QWORD playedBytes = BASS_ChannelGetPosition(streams[streamIdx], BASS_POS_BYTE);
    QWORD totalPlayableBytes = BASS_ChannelGetLength(streams[streamIdx], BASS_POS_BYTE);
    
    double downloadPct = 1.0 * downloadedBytes / totalBytes;
    double playPct = 1.0 * playedBytes / totalPlayableBytes;
    
    dbug(@"[Stream: %lu %u, identifier: %lu] Connected: %llu. Download: %.3f%%. Playback: %.3f%%.\n", (unsigned long)streamIdx, streams[streamIdx], (long)idx, connected, downloadPct, playPct);
}

#pragma mark - Playback Control

- (BassPlaybackState)currentState {
    dispatch_async(queue, ^{
        BassPlaybackState state = BASS_ChannelIsActive(self.activeStream);
        
        if(state != _currentState) {
            [self changeCurrentState:state];
        }
    });
    
    return _currentState;
}

- (void)changeCurrentState:(BassPlaybackState)state {
    dispatch_async(dispatch_get_main_queue(), ^{
        _currentState = state;
        [self.delegate BASSDownloadPlaybackStateChanged:state];
    });
}

- (NSTimeInterval)currentDuration {
    QWORD len = BASS_ChannelGetLength(self.activeStream, BASS_POS_BYTE);
    return BASS_ChannelBytes2Seconds(self.activeStream, len);
}

- (NSTimeInterval)elapsed {
    QWORD elapsedBytes = BASS_ChannelGetPosition(self.activeStream, BASS_POS_BYTE);
    return BASS_ChannelBytes2Seconds(self.activeStream, elapsedBytes);
}

- (void)next {
    dispatch_async(queue, ^{
        if(isInactiveStreamUsed) {
            [self mixInNextTrack:self.activeStream];
        }
    });
}

- (void)pause {
    dispatch_async(queue, ^{
        // no assert because it could fail if already paused
        if(BASS_ChannelPause(mixerMaster)) {
            [self changeCurrentState:BassPlaybackStatePaused];
        }
    });
}

- (void)resume {
    dispatch_async(queue, ^{
        // no assert because it could fail if already playing
        if(BASS_ChannelPlay(mixerMaster, NO)) {
            [self changeCurrentState:BassPlaybackStatePlaying];
        }
    });
}

- (void)seekToPercent:(float)pct {
    dispatch_async(queue, ^{
        [self _seekToPercent:pct];
    });
}

- (void)_seekToPercent:(float)pct {
    QWORD len = BASS_ChannelGetLength(self.activeStream, BASS_POS_BYTE);
    double duration = BASS_ChannelBytes2Seconds(self.activeStream, len);
    QWORD seekTo = BASS_ChannelSeconds2Bytes(self.activeStream, duration * pct);
    double seekToDuration = BASS_ChannelBytes2Seconds(self.activeStream, seekTo);
    
    dbug(@"[bass][stream %lu] Found length in bytes to be %llu bytes/%f. Seeking to: %llu bytes/%f", (unsigned long)activeStreamIdx, len, duration, seekTo, seekToDuration);
    
    QWORD downloadedBytes = BASS_StreamGetFilePosition(self.activeStream, BASS_FILEPOS_DOWNLOAD);
    QWORD totalFileBytes = BASS_StreamGetFilePosition(self.activeStream, BASS_FILEPOS_SIZE);
    double downloadedPct = 1.0 * downloadedBytes / totalFileBytes;
    
    if(pct > downloadedPct) {
        dbug(@"[bass][stream %lu] Seek %% (%f/%llu) is greater than downloaded %% (%f/%llu). Opening new stream.", (unsigned long)activeStreamIdx, pct, (QWORD)(pct * totalFileBytes), downloadedPct, downloadedBytes);
        
        HSTREAM oldActiveStream = self.activeStream;
        
        BASS_Mixer_ChannelRemove(oldActiveStream);
        BASS_ChannelStop(oldActiveStream);
        
        QWORD fileOffset = (QWORD)floor(pct * totalFileBytes);
        
        if([self buildAndSetupActiveStreamForURL:self.currentlyPlayingURL
                                  withIdentifier:self.currentlyPlayingIdentifier
                                       andOffset:(DWORD)fileOffset] != 0) {
            assert(BASS_Mixer_StreamAddChannel(mixerMaster, self.activeStream, BASS_STREAM_AUTOFREE | BASS_MIXER_NORAMPIN));
            assert(BASS_ChannelPlay(mixerMaster, TRUE));
        }
    }
    else {
        assert(BASS_ChannelSetPosition(self.activeStream, seekTo, BASS_POS_BYTE));
    }
}

#pragma mark - Error Helpers

- (NSError *)errorForErrorCode:(BassStreamError)erro {
    NSString *str;
    
    if(erro == BassStreamErrorInit)
        str = @"BASS_ERROR_INIT: BASS_Init has not been successfully called.";
    else if(erro == BassStreamErrorNotAvail)
        str = @"BASS_ERROR_NOTAVAIL: Only decoding channels (BASS_STREAM_DECODE) are allowed when using the \"no sound\" device. The BASS_STREAM_AUTOFREE flag is also unavailable to decoding channels.";
    else if(erro == BassStreamErrorNoInternet)
        str = @"BASS_ERROR_NONET: No internet connection could be opened. Can be caused by a bad proxy setting.";
    else if(erro == BassStreamErrorInvalidUrl)
        str = @"BASS_ERROR_ILLPARAM: url is not a valid URL.";
    else if(erro == BassStreamErrorSslUnsupported)
        str = @"BASS_ERROR_SSL: SSL/HTTPS support is not available.";
    else if(erro == BassStreamErrorServerTimeout)
        str = @"BASS_ERROR_TIMEOUT: The server did not respond to the request within the timeout period, as set with the BASS_CONFIG_NET_TIMEOUT config option.";
    else if(erro == BassStreamErrorCouldNotOpenFile)
        str = @"BASS_ERROR_FILEOPEN: The file could not be opened.";
    else if(erro == BassStreamErrorFileInvalidFormat)
        str = @"BASS_ERROR_FILEFORM: The file's format is not recognised/supported.";
    else if(erro == BassStreamErrorSupportedCodec)
        str = @"BASS_ERROR_CODEC: The file uses a codec that is not available/supported. This can apply to WAV and AIFF files, and also MP3 files when using the \"MP3-free\" BASS version.";
    else if(erro == BassStreamErrorUnsupportedSampleFormat)
        str = @"BASS_ERROR_SPEAKER: The sample format is not supported by the device/drivers. If the stream is more than stereo or the BASS_SAMPLE_FLOAT flag is used, it could be that they are not supported.";
    else if(erro == BassStreamErrorInsufficientMemory)
        str = @"BASS_ERROR_MEM: There is insufficient memory.";
    else if(erro == BassStreamErrorNo3D)
        str = @"BASS_ERROR_NO3D: Could not initialize 3D support.";
    else if(erro == BassStreamErrorUnknown)
        str = @"BASS_ERROR_UNKNOWN: Some other mystery problem! Usually this is when the Internet is available but the server/port at the specific URL isn't.";
    
    return [NSError errorWithDomain:@"com.alecgorge.ios.objectivebass"
                               code:erro
                           userInfo:@{NSLocalizedDescriptionKey: str}];
}

@end
