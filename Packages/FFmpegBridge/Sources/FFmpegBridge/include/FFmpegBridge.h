#ifndef BETTERTG_FFMPEG_BRIDGE_H
#define BETTERTG_FFMPEG_BRIDGE_H

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/frame.h>
#include <libavutil/imgutils.h>
#include <libavutil/pixdesc.h>
#include <libavutil/pixfmt.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>

const char *BetterTGFFmpegVersion(void);
int BetterTGFFmpegHasVP9Decoder(void);
int BetterTGFFmpegHasOpusDecoder(void);
int BetterTGFFmpegHasOpusEncoder(void);
int BetterTGFFmpegHasOggMuxer(void);
int BetterTGFFmpegHasGIFDecoder(void);

// Transcodes the first audio stream to a mono 48 kHz Ogg/Opus voice note.
// Returns 0 on success or a negative FFmpeg error code on failure.
int BetterTGFFmpegTranscodeVoiceNote(
    const char *inputPath,
    const char *outputPath,
    int bitrate
);

// Returns 1 only for a decodable mono 48 kHz Ogg/Opus file with positive duration.
int BetterTGFFmpegIsOggOpusFile(const char *path);

typedef struct BetterTGFFmpegAudioDecodeJob BetterTGFFmpegAudioDecodeJob;

BetterTGFFmpegAudioDecodeJob *BetterTGFFmpegAudioDecodeJobCreate(
    const char *inputPath,
    const char *outputPath,
    int64_t maximumOutputBytes
);
void BetterTGFFmpegAudioDecodeJobCancel(BetterTGFFmpegAudioDecodeJob *job);
int BetterTGFFmpegAudioDecodeJobRun(BetterTGFFmpegAudioDecodeJob *job);
void BetterTGFFmpegAudioDecodeJobDestroy(BetterTGFFmpegAudioDecodeJob *job);

typedef struct BetterTGFFmpegVideoDecoder BetterTGFFmpegVideoDecoder;

BetterTGFFmpegVideoDecoder *BetterTGFFmpegVideoDecoderCreate(const char *path);
void BetterTGFFmpegVideoDecoderDestroy(BetterTGFFmpegVideoDecoder *decoder);
int BetterTGFFmpegVideoDecoderWidth(const BetterTGFFmpegVideoDecoder *decoder);
int BetterTGFFmpegVideoDecoderHeight(const BetterTGFFmpegVideoDecoder *decoder);
double BetterTGFFmpegVideoDecoderFrameRate(const BetterTGFFmpegVideoDecoder *decoder);
double BetterTGFFmpegVideoDecoderDuration(const BetterTGFFmpegVideoDecoder *decoder);
int BetterTGFFmpegVideoDecoderReset(BetterTGFFmpegVideoDecoder *decoder);

// Consumes a decoded frame without pixel conversion. Missing PTS is NAN.
// Returns 1 for a frame, 0 only at native EOF, and -1 on failure.
int BetterTGFFmpegVideoDecoderReadTiming(
    BetterTGFFmpegVideoDecoder *decoder,
    double *presentationTime,
    double *frameDuration
);

// Returns 1 for a decoded frame, 0 at end of stream, and -1 on failure.
int BetterTGFFmpegVideoDecoderReadFrame(
    BetterTGFFmpegVideoDecoder *decoder,
    uint8_t *destination,
    int destinationWidth,
    int destinationHeight,
    int destinationBytesPerRow,
    double *presentationTime,
    double *frameDuration,
    int *hasAlpha
);

typedef int (*BetterTGFFmpegRangeReadCallback)(
    void *context,
    int64_t offset,
    uint8_t *destination,
    int destinationCapacity
);

typedef struct BetterTGFFmpegLookaheadJob BetterTGFFmpegLookaheadJob;

BetterTGFFmpegLookaheadJob *BetterTGFFmpegLookaheadJobCreate(
    void *context,
    int64_t fileSize,
    BetterTGFFmpegRangeReadCallback readCallback
);
void BetterTGFFmpegLookaheadJobCancel(BetterTGFFmpegLookaheadJob *job);

// Opens the custom AVIO input, seeks to seekTime, and demuxes until every
// present audio/video stream reaches seekTime + lookaheadDuration or EOF.
// Returns 1 on success, 0 on FFmpeg/read failure, or -1 on cancellation.
int BetterTGFFmpegLookaheadJobRun(
    BetterTGFFmpegLookaheadJob *job,
    double seekTime,
    double lookaheadDuration
);
void BetterTGFFmpegLookaheadJobDestroy(BetterTGFFmpegLookaheadJob *job);

int BetterTGFFmpegLookaheadJobHasAudio(const BetterTGFFmpegLookaheadJob *job);
int BetterTGFFmpegLookaheadJobHasVideo(const BetterTGFFmpegLookaheadJob *job);
int BetterTGFFmpegLookaheadJobIsEnded(const BetterTGFFmpegLookaheadJob *job);
double BetterTGFFmpegLookaheadJobAudioReadableTo(const BetterTGFFmpegLookaheadJob *job);
double BetterTGFFmpegLookaheadJobVideoReadableTo(const BetterTGFFmpegLookaheadJob *job);
double BetterTGFFmpegLookaheadJobDuration(const BetterTGFFmpegLookaheadJob *job);
int64_t BetterTGFFmpegLookaheadJobBytesRead(const BetterTGFFmpegLookaheadJob *job);
int BetterTGFFmpegLookaheadJobReadCallCount(const BetterTGFFmpegLookaheadJob *job);
int BetterTGFFmpegLookaheadJobSeekCallCount(const BetterTGFFmpegLookaheadJob *job);
int BetterTGFFmpegLookaheadJobSizeCallCount(const BetterTGFFmpegLookaheadJob *job);
int BetterTGFFmpegLookaheadJobErrorCode(const BetterTGFFmpegLookaheadJob *job);

typedef int (*BetterTGFFmpegVideoFrameCallback)(
    void *context,
    const uint8_t *bytes,
    int width,
    int height,
    int bytesPerRow,
    double presentationTime,
    double frameDuration,
    int isKeyFrame
);

typedef int (*BetterTGFFmpegPlaybackMetadataCallback)(
    void *context,
    int hasAudio,
    int hasVideo,
    int videoCodecID,
    int audioCodecID,
    double duration,
    int hasExplicitDuration,
    double timelineOrigin,
    double videoStartTime,
    double videoEndTime,
    double audioStartTime,
    double audioEndTime
);

typedef int (*BetterTGFFmpegAudioFrameCallback)(
    void *context,
    const float *samples,
    int frameCount,
    int channelCount,
    int sampleRate,
    double presentationTime
);

typedef struct BetterTGFFmpegPlaybackJob BetterTGFFmpegPlaybackJob;

BetterTGFFmpegPlaybackJob *BetterTGFFmpegPlaybackJobCreate(
    void *context,
    int64_t fileSize,
    BetterTGFFmpegRangeReadCallback readCallback,
    BetterTGFFmpegPlaybackMetadataCallback metadataCallback,
    BetterTGFFmpegVideoFrameCallback videoCallback,
    BetterTGFFmpegAudioFrameCallback audioCallback
);
void BetterTGFFmpegPlaybackJobCancel(BetterTGFFmpegPlaybackJob *job);

// Decodes at most decodeDuration seconds beginning at seekTime. Returns 1 on
// success, 0 on FFmpeg/read/callback failure, or -1 on cancellation.
int BetterTGFFmpegPlaybackJobRun(
    BetterTGFFmpegPlaybackJob *job,
    double seekTime,
    double decodeDuration
);

// Starts one persistent decode session. Later Continue calls extend its
// internal absolute horizon without reopening or flushing decoder state.
// Crossing frames are emitted whole except at the main video-or-audio track end.
// Run/Start/Continue/Destroy are serialized;
// Cancel is terminal and may be called from another thread.
int BetterTGFFmpegPlaybackJobStartPersistent(
    BetterTGFFmpegPlaybackJob *job,
    double seekTime,
    double decodeDuration
);
int BetterTGFFmpegPlaybackJobContinue(
    BetterTGFFmpegPlaybackJob *job,
    double decodeDuration
);
void BetterTGFFmpegPlaybackJobDestroy(BetterTGFFmpegPlaybackJob *job);

int BetterTGFFmpegPlaybackJobHasAudio(const BetterTGFFmpegPlaybackJob *job);
int BetterTGFFmpegPlaybackJobHasVideo(const BetterTGFFmpegPlaybackJob *job);
int BetterTGFFmpegPlaybackJobIsEnded(const BetterTGFFmpegPlaybackJob *job);
int BetterTGFFmpegPlaybackJobVideoCodecID(const BetterTGFFmpegPlaybackJob *job);
int BetterTGFFmpegPlaybackJobAudioCodecID(const BetterTGFFmpegPlaybackJob *job);
int BetterTGFFmpegPlaybackJobVideoIsVP9(const BetterTGFFmpegPlaybackJob *job);
int BetterTGFFmpegPlaybackJobAudioIsOpus(const BetterTGFFmpegPlaybackJob *job);
int BetterTGFFmpegPlaybackJobVideoFrameCount(const BetterTGFFmpegPlaybackJob *job);
int BetterTGFFmpegPlaybackJobAudioFrameCount(const BetterTGFFmpegPlaybackJob *job);
double BetterTGFFmpegPlaybackJobVideoDecodedTo(const BetterTGFFmpegPlaybackJob *job);
double BetterTGFFmpegPlaybackJobAudioDecodedTo(const BetterTGFFmpegPlaybackJob *job);
double BetterTGFFmpegPlaybackJobContinuationTime(const BetterTGFFmpegPlaybackJob *job);
double BetterTGFFmpegPlaybackJobDuration(const BetterTGFFmpegPlaybackJob *job);
// True only for the selected main track's own end metadata, never a container estimate.
int BetterTGFFmpegPlaybackJobHasExplicitDuration(const BetterTGFFmpegPlaybackJob *job);
// True at EOF when explicit metadata or observed main-track frames establish the end.
int BetterTGFFmpegPlaybackJobHasFinalDuration(const BetterTGFFmpegPlaybackJob *job);
double BetterTGFFmpegPlaybackJobTimelineOrigin(const BetterTGFFmpegPlaybackJob *job);
int64_t BetterTGFFmpegPlaybackJobBytesRead(const BetterTGFFmpegPlaybackJob *job);
int BetterTGFFmpegPlaybackJobReadCallCount(const BetterTGFFmpegPlaybackJob *job);
int BetterTGFFmpegPlaybackJobSeekCallCount(const BetterTGFFmpegPlaybackJob *job);
int BetterTGFFmpegPlaybackJobSizeCallCount(const BetterTGFFmpegPlaybackJob *job);
int BetterTGFFmpegPlaybackJobOpenCount(const BetterTGFFmpegPlaybackJob *job);
int BetterTGFFmpegPlaybackJobRunCount(const BetterTGFFmpegPlaybackJob *job);
int BetterTGFFmpegPlaybackJobExplicitSeekCount(const BetterTGFFmpegPlaybackJob *job);
int BetterTGFFmpegPlaybackJobMaximumPendingPacketCount(const BetterTGFFmpegPlaybackJob *job);
int64_t BetterTGFFmpegPlaybackJobMaximumPendingPacketBytes(const BetterTGFFmpegPlaybackJob *job);
int BetterTGFFmpegPlaybackJobErrorCode(const BetterTGFFmpegPlaybackJob *job);

#endif
