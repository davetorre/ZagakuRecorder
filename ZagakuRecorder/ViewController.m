#import "ViewController.h"
@import AudioToolbox;
@import AVFoundation;
#import "TPCircularBuffer.h"

@interface ViewController ()
@end


static void CheckStatus(OSStatus error, const char *operation) {
    if (error == noErr) {
        return;
    }
    char str[20];
    *(UInt32 *) (str + 1) = CFSwapInt32HostToBig(error);
    if (isprint(str[1]) && isprint(str[2]) && isprint(str[3]) && isprint(str[4])) {
        str[0] = str[5] = '\'';
        str[6] = '\0';
    } else {
        sprintf(str, "%d", (int)error);
    }
    fprintf(stderr, "[Error] %s (%s)\n", operation, str);
    exit(1);
}


AudioComponentInstance recorder;
ExtAudioFileRef audioFileRef;
TPCircularBuffer circularBuffer;
NSTimer *timer;

static OSStatus recordingCallback(void *InRefCon,
                                  AudioUnitRenderActionFlags *ioActionFlags,
                                  const AudioTimeStamp *inTimeStamp,
                                  UInt32 inBusNumber,
                                  UInt32 inNumberFrames,
                                  AudioBufferList *ioData) {
    AudioBuffer buffer;
    buffer.mNumberChannels = 1;
    buffer.mDataByteSize = inNumberFrames * sizeof(SInt16);
    buffer.mData = malloc(buffer.mDataByteSize);
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0] = buffer;
    
    OSStatus status = AudioUnitRender(recorder, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, &bufferList);
    if (status != noErr) {
        printf("record callback 1\n");
        return -1;
    }
    TPCircularBufferProduceBytes(&circularBuffer, bufferList.mBuffers[0].mData, buffer.mDataByteSize);

    
//    SInt16 *frameBuffer = buffer.mData;
//    for (int i = 0; i < inNumberFrames; i++) {
//        printf("%i\n", frameBuffer[i]);
//    }

    
    return noErr;
}


@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupRecorder];
    int bufferLength = 44100;
    TPCircularBufferInit(&circularBuffer, bufferLength);
}


- (void)setupRecorder {
    // Set up audio format
    AudioStreamBasicDescription audioFormat;
    audioFormat.mSampleRate = 44100;
    audioFormat.mFormatID = kAudioFormatLinearPCM;
    audioFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    audioFormat.mFramesPerPacket = 1;
    audioFormat.mChannelsPerFrame = 1;
    audioFormat.mBitsPerChannel = 16;
    audioFormat.mBytesPerFrame = audioFormat.mChannelsPerFrame * sizeof(SInt16);
    audioFormat.mBytesPerPacket = audioFormat.mFramesPerPacket * audioFormat.mBytesPerFrame;
    
    
    // Get recorder
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    CheckStatus(AudioComponentInstanceNew(comp, &recorder), "recorder setup 1");
    
    
    // Enable only input on recorder
    UInt32 enable = 1;
    UInt32 disable = 0;
    UInt32 inputBus = 1;
    UInt32 outputBus = 0;
    CheckStatus(AudioUnitSetProperty(recorder,
                                     kAudioOutputUnitProperty_EnableIO,
                                     kAudioUnitScope_Input,
                                     inputBus,
                                     &enable,
                                     sizeof(enable)),
                "recorder setup 2");
    CheckStatus(AudioUnitSetProperty(recorder,
                                     kAudioOutputUnitProperty_EnableIO,
                                     kAudioUnitScope_Output,
                                     outputBus,
                                     &disable,
                                     sizeof(disable)),
                "recorder setup 3");
    
    
    // Set audio format for recorder
    CheckStatus(AudioUnitSetProperty(recorder,
                                     kAudioUnitProperty_StreamFormat,
                                     kAudioUnitScope_Output,
                                     inputBus,
                                     &audioFormat,
                                     sizeof(audioFormat)),
                "recorder setup 4");
    
    
    // Set recorder callback
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = recordingCallback;
    callbackStruct.inputProcRefCon = (__bridge void*)self;
    CheckStatus(AudioUnitSetProperty(recorder,
                                     kAudioOutputUnitProperty_SetInputCallback,
                                     kAudioUnitScope_Global,
                                     inputBus,
                                     &callbackStruct,
                                     sizeof(callbackStruct)),
                "recorder setup 5");
    
    
    // Initialize recorder
    CheckStatus(AudioUnitInitialize(recorder), "recorder setup 6");
    
    
    // Create output file with audio format
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *appFile = [documentsDirectory stringByAppendingPathComponent:@"audiofile.wav"];
    NSURL *audioFileURL = [NSURL URLWithString:appFile];
    CheckStatus(ExtAudioFileCreateWithURL((__bridge CFURLRef)audioFileURL,
                                          kAudioFileWAVEType,
                                          &audioFormat,
                                          NULL,
                                          kAudioFileFlags_EraseFile,
                                          &audioFileRef),
                "recorder setup 7");
    CheckStatus(ExtAudioFileSetProperty(audioFileRef,
                                        kExtAudioFileProperty_ClientDataFormat,
                                        sizeof(audioFormat),
                                        &audioFormat),
                "recorder setup 8");
}

- (void)printSamples:(NSTimer *)timer {
    int32_t availableBytes;
    SInt16 *buffer = TPCircularBufferTail(&circularBuffer, &availableBytes);
    int numSamples = 22050;
// //   memcpy(targetBuffer, buffer, MIN(numSamples * sizeof(SInt16), availableBytes));
//    printf("new group\n");
//    for (int i = 0; i < numSamples; i++) {
//        printf("%i\n", buffer[i]);
//    }
    AudioBuffer buffer2;
    buffer2.mNumberChannels = 1;
    buffer2.mDataByteSize = numSamples * sizeof(SInt16);
    buffer2.mData = malloc(buffer2.mDataByteSize);
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0] = buffer2;
    buffer2.mData = buffer;
    OSStatus status = ExtAudioFileWrite(audioFileRef, numSamples, &bufferList);
    if (status != noErr) {
        printf("record callback 2\n");
    }
    
    TPCircularBufferConsume(&circularBuffer, numSamples);
    
}

- (IBAction)recordButtonPressed:(id)sender {
    NSError *error;
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    if (error != nil) {
        NSAssert(error == nil, @"record 1");
    }
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryRecord error:&error];
    if (error != nil) {
        NSAssert(error == nil, @"record 2");
    }
    [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
        if (granted) {
            CheckStatus(AudioOutputUnitStart(recorder), "record 3");
            timer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                     target:self
                                                   selector:@selector(printSamples:)
                                                   userInfo:nil
                                                    repeats:YES];
//            dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
//            dispatch_async(queue, ^{
//                NSLog(@"hi mom");
//            });
            NSLog(@"started recording");
        } else {
            NSLog(@"No permission");
        }
    }];
}


- (IBAction)stopButtonPressed:(id)sender {
    CheckStatus(AudioOutputUnitStop(recorder), "stop recorder 1");
    NSError *error;
    [[AVAudioSession sharedInstance] setActive:NO error:&error];
    if (error != nil) {
        NSAssert(error == nil, @"stop recorder 2");
    }
//    int32_t availableBytes = 22050;
//    SInt16 *buffer = TPCircularBufferTail(&circularBuffer, &availableBytes);
//    for (int i = 0; i < availableBytes; i++) {
//        printf("%i\n", buffer[i]);
//    }
    [timer invalidate];
    timer = nil;
    CheckStatus(ExtAudioFileDispose(audioFileRef), "stop recorder 3");
    NSURL *location = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                              inDomains:NSUserDomainMask] lastObject];
    NSLog(@"Audio file in: %@", location);
    NSLog(@"stopped recording");
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
