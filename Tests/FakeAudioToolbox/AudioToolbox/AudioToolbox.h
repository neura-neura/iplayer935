#include <stdint.h>
#include <stdbool.h>
typedef int32_t OSStatus;
typedef uint32_t UInt32;
typedef struct { double mSampleRate; UInt32 mFormatID,mFormatFlags,mBytesPerPacket,mFramesPerPacket,mBytesPerFrame,mChannelsPerFrame,mBitsPerChannel,mReserved; } AudioStreamBasicDescription;
typedef struct { UInt32 mAudioDataBytesCapacity; void *mAudioData; UInt32 mAudioDataByteSize; } AudioQueueBuffer;
typedef AudioQueueBuffer *AudioQueueBufferRef;
typedef struct IPFakeAudioQueue *AudioQueueRef;
typedef void (*AudioQueueOutputCallback)(void *, AudioQueueRef, AudioQueueBufferRef);
enum { kAudioFormatLinearPCM=1, kAudioFormatFlagIsSignedInteger=4, kAudioFormatFlagIsPacked=8 };
OSStatus AudioQueueNewOutput(const AudioStreamBasicDescription *, AudioQueueOutputCallback, void *, void *, void *, UInt32, AudioQueueRef *);
OSStatus AudioQueueAllocateBuffer(AudioQueueRef, UInt32, AudioQueueBufferRef *);
OSStatus AudioQueueFreeBuffer(AudioQueueRef, AudioQueueBufferRef);
OSStatus AudioQueueEnqueueBuffer(AudioQueueRef, AudioQueueBufferRef, UInt32, const void *);
OSStatus AudioQueueStart(AudioQueueRef, const void *);
OSStatus AudioQueuePause(AudioQueueRef);
OSStatus AudioQueueStop(AudioQueueRef, bool);
OSStatus AudioQueueReset(AudioQueueRef);
OSStatus AudioQueueDispose(AudioQueueRef, bool);

enum { kAudioQueueParam_Volume=1 };
OSStatus AudioQueueSetParameter(AudioQueueRef, UInt32, float);
