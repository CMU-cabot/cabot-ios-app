/*******************************************************************************
 * Copyright (c) 2021  Carnegie Mellon University
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *******************************************************************************/

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
//#import <HLPLocationManager/HLPLocation.h>

#define SPEECH_SPEED @"speech_speed"

typedef enum {
    SpeechSoundEffectCaution,
    SpeechSoundEffectLandmark,
    SpeechSoundEffectDirection
} SpeechSoundEffectType;

typedef enum {
    SpeechPriorityImmediate,
    SpeechPriorityWithinArea,
    SpeechPriorityCanBeDelayed,
} SpeechPriority;

@interface HLPSpeechEntry : NSObject
@property double pauseDuration;
@property (strong, nonatomic) AVSpeechUtterance *ut;
@property SpeechSoundEffectType type;
@property SpeechPriority priority;
@property NSTimeInterval validBy;
@property double validRadius; // in meter
@property (strong, nonatomic) void (^completionHandler)(int);
@property (strong, nonatomic) void (^progressHandler)(NSString*, int, NSRange);
@property int progressCount;
@property NSMutableArray<NSValue *> *ranges;
@property NSTimeInterval issued;
@property NSTimeInterval speakStart;
@property NSTimeInterval speakFinish;
@property NSTimer *voWatchTimer;
@property BOOL selfvoicing;
@property BOOL quickAnswer;
@end

@interface NavDeviceTTS : NSObject <AVSpeechSynthesizerDelegate>{
    BOOL isSpeaking;
    BOOL isProcessing;
    NSMutableArray *speaking;
    NSMutableDictionary *processing;
    AVSpeechSynthesizer *voice;
    NSTimer *speakTimer;
}

+ (instancetype) sharedTTS;
+ (NSString *)removeDots:(NSString *)str;

- (AVSpeechUtterance*) speak:(NSString*)text withOptions:(NSDictionary*)options completionHandler:(void(^)(int))handler progressHandler:(void (^)(NSString*, int, NSRange))phandler;

- (void) pause:(double)duration;
- (void) reset;
- (void) stop:(BOOL)immediate;
- (BOOL) isSpeaking;

@end
    
