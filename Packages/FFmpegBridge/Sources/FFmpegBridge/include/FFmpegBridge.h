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

#endif
