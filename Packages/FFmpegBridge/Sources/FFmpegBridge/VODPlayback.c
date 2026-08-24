#include "FFmpegBridge.h"

#include <libavformat/avio.h>
#include <libavutil/channel_layout.h>
#include <libavutil/imgutils.h>
#include <libavutil/mathematics.h>

#include <errno.h>
#include <limits.h>
#include <math.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define BETTERTG_PLAYBACK_AVIO_BUFFER_SIZE (64 * 1024)
#define BETTERTG_PLAYBACK_MAXIMUM_READ_SIZE (256 * 1024)
#define BETTERTG_PLAYBACK_MAXIMUM_READ_CALLS 100000
#define BETTERTG_PLAYBACK_MAXIMUM_PACKET_COUNT 1000000
#define BETTERTG_PLAYBACK_MAXIMUM_READ_BUDGET (512LL * 1024 * 1024)
#define BETTERTG_PLAYBACK_MAXIMUM_DIMENSION 4096
#define BETTERTG_PLAYBACK_MAXIMUM_PIXELS (16 * 1024 * 1024)
#define BETTERTG_PLAYBACK_AUDIO_SAMPLE_RATE 48000

struct BetterTGFFmpegPlaybackJob {
    void *context;
    BetterTGFFmpegRangeReadCallback readCallback;
    BetterTGFFmpegVideoFrameCallback videoCallback;
    BetterTGFFmpegAudioFrameCallback audioCallback;
    int64_t fileSize;
    int64_t readingOffset;
    atomic_int cancelled;

    AVFormatContext *formatContext;
    AVIOContext *ioContext;
    AVCodecContext *videoCodecContext;
    AVCodecContext *audioCodecContext;
    AVFrame *videoFrame;
    AVFrame *audioFrame;
    AVPacket *packet;
    struct SwsContext *scaleContext;
    SwrContext *resampleContext;
    int videoStreamIndex;
    int audioStreamIndex;
    AVRational videoTimeBase;
    AVRational audioTimeBase;
    double videoFrameRate;
    double duration;
    double videoDecodedTo;
    double audioDecodedTo;
    double nextAudioTime;
    int outputAudioChannels;
    int ended;
    int videoFrameCount;
    int audioFrameCount;
    int64_t bytesRead;
    int readCallCount;
    int seekCallCount;
    int sizeCallCount;
    int errorCode;
};

static int BetterTGFFmpegPlaybackIsCancelled(
    const BetterTGFFmpegPlaybackJob *job
) {
    return job == NULL || atomic_load_explicit(&job->cancelled, memory_order_relaxed) != 0;
}

static int BetterTGFFmpegPlaybackInterrupt(void *opaque) {
    return BetterTGFFmpegPlaybackIsCancelled((BetterTGFFmpegPlaybackJob *)opaque);
}

static int BetterTGFFmpegPlaybackRead(
    void *opaque,
    uint8_t *destination,
    int destinationCapacity
) {
    BetterTGFFmpegPlaybackJob *job = opaque;
    if (job == NULL || destination == NULL || destinationCapacity <= 0 ||
        job->readCallback == NULL) {
        return AVERROR(EINVAL);
    }
    if (BetterTGFFmpegPlaybackIsCancelled(job)) {
        return AVERROR_EXIT;
    }
    if (job->readingOffset >= job->fileSize) {
        return AVERROR_EOF;
    }
    if (job->readCallCount >= BETTERTG_PLAYBACK_MAXIMUM_READ_CALLS ||
        job->bytesRead >= BETTERTG_PLAYBACK_MAXIMUM_READ_BUDGET) {
        return AVERROR(EFBIG);
    }

    const int64_t remaining = job->fileSize - job->readingOffset;
    int capacity = destinationCapacity;
    if (capacity > BETTERTG_PLAYBACK_MAXIMUM_READ_SIZE) {
        capacity = BETTERTG_PLAYBACK_MAXIMUM_READ_SIZE;
    }
    if ((int64_t)capacity > remaining) {
        capacity = (int)remaining;
    }
    const int64_t budgetRemaining = BETTERTG_PLAYBACK_MAXIMUM_READ_BUDGET - job->bytesRead;
    if ((int64_t)capacity > budgetRemaining) {
        capacity = (int)budgetRemaining;
    }
    if (capacity <= 0) {
        return AVERROR_EOF;
    }

    job->readCallCount += 1;
    const int result = job->readCallback(
        job->context,
        job->readingOffset,
        destination,
        capacity
    );
    if (result > capacity) {
        return AVERROR(EIO);
    }
    if (result > 0) {
        job->readingOffset += result;
        job->bytesRead += result;
        return result;
    }
    if (result == 0) {
        return AVERROR_EOF;
    }
    return result == -1 ? AVERROR_EXIT : AVERROR(EIO);
}

static int BetterTGFFmpegPlaybackCheckedAdd(
    int64_t left,
    int64_t right,
    int64_t *result
) {
    if ((right > 0 && left > INT64_MAX - right) ||
        (right < 0 && left < INT64_MIN - right)) {
        return 0;
    }
    *result = left + right;
    return 1;
}

static int64_t BetterTGFFmpegPlaybackSeek(
    void *opaque,
    int64_t offset,
    int whence
) {
    BetterTGFFmpegPlaybackJob *job = opaque;
    if (job == NULL) {
        return AVERROR(EINVAL);
    }
    if ((whence & AVSEEK_SIZE) != 0) {
        job->sizeCallCount += 1;
        return job->fileSize;
    }
    if (BetterTGFFmpegPlaybackIsCancelled(job)) {
        return AVERROR_EXIT;
    }

    whence &= ~AVSEEK_FORCE;
    int64_t base = 0;
    switch (whence) {
        case SEEK_SET:
            base = 0;
            break;
        case SEEK_CUR:
            base = job->readingOffset;
            break;
        case SEEK_END:
            base = job->fileSize;
            break;
        default:
            return AVERROR(EINVAL);
    }
    int64_t target = 0;
    if (!BetterTGFFmpegPlaybackCheckedAdd(base, offset, &target) ||
        target < 0 || target > job->fileSize) {
        return AVERROR(EINVAL);
    }
    job->readingOffset = target;
    job->seekCallCount += 1;
    return target;
}

static void BetterTGFFmpegPlaybackClose(BetterTGFFmpegPlaybackJob *job) {
    if (job == NULL) {
        return;
    }
    swr_free(&job->resampleContext);
    sws_freeContext(job->scaleContext);
    av_packet_free(&job->packet);
    av_frame_free(&job->audioFrame);
    av_frame_free(&job->videoFrame);
    avcodec_free_context(&job->audioCodecContext);
    avcodec_free_context(&job->videoCodecContext);
    avformat_close_input(&job->formatContext);
    if (job->ioContext != NULL) {
        av_freep(&job->ioContext->buffer);
    }
    avio_context_free(&job->ioContext);
}

static int BetterTGFFmpegPlaybackFindStream(
    const BetterTGFFmpegPlaybackJob *job,
    enum AVMediaType mediaType
) {
    for (unsigned int index = 0; index < job->formatContext->nb_streams; index++) {
        const AVStream *stream = job->formatContext->streams[index];
        if (stream->codecpar->codec_type != mediaType) {
            continue;
        }
        if (mediaType == AVMEDIA_TYPE_VIDEO &&
            (stream->disposition & AV_DISPOSITION_ATTACHED_PIC) != 0) {
            continue;
        }
        return (int)index;
    }
    return -1;
}

static int BetterTGFFmpegPlaybackOpenCodec(
    BetterTGFFmpegPlaybackJob *job,
    int streamIndex,
    AVCodecContext **codecContext
) {
    if (streamIndex < 0) {
        return 0;
    }
    AVStream *stream = job->formatContext->streams[streamIndex];
    const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (codec == NULL) {
        return AVERROR_DECODER_NOT_FOUND;
    }
    AVCodecContext *context = avcodec_alloc_context3(codec);
    if (context == NULL) {
        return AVERROR(ENOMEM);
    }
    int result = avcodec_parameters_to_context(context, stream->codecpar);
    if (result >= 0) {
        result = avcodec_open2(context, codec, NULL);
    }
    if (result < 0) {
        avcodec_free_context(&context);
        return result;
    }
    *codecContext = context;
    return 0;
}

static double BetterTGFFmpegPlaybackStreamDuration(const AVStream *stream) {
    if (stream == NULL || stream->duration == AV_NOPTS_VALUE ||
        stream->time_base.num <= 0 || stream->time_base.den <= 0) {
        return 0.0;
    }
    return fmax(0.0, (double)stream->duration * av_q2d(stream->time_base));
}

static int BetterTGFFmpegPlaybackOpen(BetterTGFFmpegPlaybackJob *job) {
    uint8_t *buffer = av_malloc(BETTERTG_PLAYBACK_AVIO_BUFFER_SIZE);
    if (buffer == NULL) {
        return AVERROR(ENOMEM);
    }
    job->ioContext = avio_alloc_context(
        buffer,
        BETTERTG_PLAYBACK_AVIO_BUFFER_SIZE,
        0,
        job,
        BetterTGFFmpegPlaybackRead,
        NULL,
        BetterTGFFmpegPlaybackSeek
    );
    if (job->ioContext == NULL) {
        av_free(buffer);
        return AVERROR(ENOMEM);
    }
    job->ioContext->seekable = AVIO_SEEKABLE_NORMAL;
    job->formatContext = avformat_alloc_context();
    if (job->formatContext == NULL) {
        return AVERROR(ENOMEM);
    }
    job->formatContext->pb = job->ioContext;
    // Decoding must retain packets consumed by stream probing. NOBUFFER is safe
    // for the packet-only lookahead job, but drops the leading WebM keyframe
    // before the VP9 decoder can see it.
    job->formatContext->flags |= AVFMT_FLAG_CUSTOM_IO | AVFMT_FLAG_FAST_SEEK;
    job->formatContext->interrupt_callback.callback = BetterTGFFmpegPlaybackInterrupt;
    job->formatContext->interrupt_callback.opaque = job;

    AVDictionary *options = NULL;
    av_dict_set(&options, "usetoc", "1", 0);
    int result = avformat_open_input(&job->formatContext, NULL, NULL, &options);
    av_dict_free(&options);
    if (result < 0) {
        return result;
    }
    result = avformat_find_stream_info(job->formatContext, NULL);
    if (result < 0) {
        return result;
    }

    job->videoStreamIndex = BetterTGFFmpegPlaybackFindStream(job, AVMEDIA_TYPE_VIDEO);
    job->audioStreamIndex = BetterTGFFmpegPlaybackFindStream(job, AVMEDIA_TYPE_AUDIO);
    if (job->videoStreamIndex < 0 && job->audioStreamIndex < 0) {
        return AVERROR_STREAM_NOT_FOUND;
    }
    result = BetterTGFFmpegPlaybackOpenCodec(
        job,
        job->videoStreamIndex,
        &job->videoCodecContext
    );
    if (result < 0) {
        return result;
    }
    result = BetterTGFFmpegPlaybackOpenCodec(
        job,
        job->audioStreamIndex,
        &job->audioCodecContext
    );
    if (result < 0) {
        return result;
    }

    if (job->videoStreamIndex >= 0) {
        AVStream *stream = job->formatContext->streams[job->videoStreamIndex];
        job->videoTimeBase = stream->time_base;
        const AVRational frameRate = av_guess_frame_rate(job->formatContext, stream, NULL);
        job->videoFrameRate = frameRate.den != 0 ? av_q2d(frameRate) : 0.0;
        job->duration = fmax(job->duration, BetterTGFFmpegPlaybackStreamDuration(stream));
        if (job->videoCodecContext->width <= 0 || job->videoCodecContext->height <= 0 ||
            job->videoCodecContext->width > BETTERTG_PLAYBACK_MAXIMUM_DIMENSION ||
            job->videoCodecContext->height > BETTERTG_PLAYBACK_MAXIMUM_DIMENSION ||
            (int64_t)job->videoCodecContext->width * job->videoCodecContext->height >
                BETTERTG_PLAYBACK_MAXIMUM_PIXELS) {
            return AVERROR(EINVAL);
        }
        job->videoFrame = av_frame_alloc();
    }
    if (job->audioStreamIndex >= 0) {
        AVStream *stream = job->formatContext->streams[job->audioStreamIndex];
        job->audioTimeBase = stream->time_base;
        job->duration = fmax(job->duration, BetterTGFFmpegPlaybackStreamDuration(stream));
        job->audioFrame = av_frame_alloc();
        if (job->audioCodecContext->sample_rate <= 0 ||
            job->audioCodecContext->ch_layout.nb_channels <= 0 ||
            job->audioCodecContext->ch_layout.nb_channels > 64) {
            return AVERROR(EINVAL);
        }
        job->outputAudioChannels = job->audioCodecContext->ch_layout.nb_channels > 1 ? 2 : 1;
        AVChannelLayout outputLayout;
        av_channel_layout_default(&outputLayout, job->outputAudioChannels);
        result = swr_alloc_set_opts2(
            &job->resampleContext,
            &outputLayout,
            AV_SAMPLE_FMT_FLT,
            BETTERTG_PLAYBACK_AUDIO_SAMPLE_RATE,
            &job->audioCodecContext->ch_layout,
            job->audioCodecContext->sample_fmt,
            job->audioCodecContext->sample_rate,
            0,
            NULL
        );
        av_channel_layout_uninit(&outputLayout);
        if (result < 0 || job->resampleContext == NULL || swr_init(job->resampleContext) < 0) {
            return result < 0 ? result : AVERROR(EINVAL);
        }
    }
    if ((job->videoStreamIndex >= 0 && job->videoFrame == NULL) ||
        (job->audioStreamIndex >= 0 && job->audioFrame == NULL)) {
        return AVERROR(ENOMEM);
    }
    if (job->duration <= 0.0 && job->formatContext->duration != AV_NOPTS_VALUE) {
        job->duration = fmax(0.0, (double)job->formatContext->duration / AV_TIME_BASE);
    }
    job->packet = av_packet_alloc();
    return job->packet != NULL ? 0 : AVERROR(ENOMEM);
}

static double BetterTGFFmpegPlaybackFrameTime(
    const AVFrame *frame,
    AVRational timeBase,
    double fallback
) {
    const int64_t timestamp = frame->best_effort_timestamp;
    if (timestamp == AV_NOPTS_VALUE || timeBase.num <= 0 || timeBase.den <= 0) {
        return fallback;
    }
    const double value = (double)timestamp * av_q2d(timeBase);
    return isfinite(value) ? fmax(0.0, value) : fallback;
}

static int BetterTGFFmpegPlaybackDrainVideo(
    BetterTGFFmpegPlaybackJob *job,
    double seekTime,
    double targetTime
) {
    if (job->videoCodecContext == NULL || job->videoFrame == NULL) {
        return 1;
    }
    for (;;) {
        if (BetterTGFFmpegPlaybackIsCancelled(job)) {
            return -1;
        }
        av_frame_unref(job->videoFrame);
        const int result = avcodec_receive_frame(job->videoCodecContext, job->videoFrame);
        if (result == AVERROR(EAGAIN) || result == AVERROR_EOF) {
            return 1;
        }
        if (result < 0) {
            job->errorCode = result;
            return 0;
        }

        const int width = job->videoCodecContext->width;
        const int height = job->videoCodecContext->height;
        const int frameWidth = job->videoFrame->width;
        const int frameHeight = job->videoFrame->height;
        if (width <= 0 || height <= 0 || frameWidth <= 0 || frameHeight <= 0 ||
            width > BETTERTG_PLAYBACK_MAXIMUM_DIMENSION ||
            height > BETTERTG_PLAYBACK_MAXIMUM_DIMENSION ||
            frameWidth > BETTERTG_PLAYBACK_MAXIMUM_DIMENSION ||
            frameHeight > BETTERTG_PLAYBACK_MAXIMUM_DIMENSION ||
            (int64_t)width * height > BETTERTG_PLAYBACK_MAXIMUM_PIXELS ||
            (int64_t)frameWidth * frameHeight > BETTERTG_PLAYBACK_MAXIMUM_PIXELS ||
            job->videoFrame->format == AV_PIX_FMT_NONE) {
            job->errorCode = AVERROR(EINVAL);
            return 0;
        }
        const size_t bytesPerRow = (size_t)width * 4;
        if ((size_t)height > SIZE_MAX / bytesPerRow || bytesPerRow > INT_MAX) {
            job->errorCode = AVERROR(EINVAL);
            return 0;
        }
        uint8_t *output = av_mallocz(bytesPerRow * (size_t)height);
        if (output == NULL) {
            job->errorCode = AVERROR(ENOMEM);
            return 0;
        }
        job->scaleContext = sws_getCachedContext(
            job->scaleContext,
            job->videoFrame->width,
            job->videoFrame->height,
            (enum AVPixelFormat)job->videoFrame->format,
            width,
            height,
            AV_PIX_FMT_BGRA,
            SWS_BILINEAR,
            NULL,
            NULL,
            NULL
        );
        uint8_t *planes[4] = { output, NULL, NULL, NULL };
        int lineSizes[4] = { (int)bytesPerRow, 0, 0, 0 };
        const int scaled = job->scaleContext != NULL
            ? sws_scale(
                job->scaleContext,
                (const uint8_t *const *)job->videoFrame->data,
                job->videoFrame->linesize,
                0,
                job->videoFrame->height,
                planes,
                lineSizes
            )
            : 0;
        if (scaled != height) {
            av_free(output);
            job->errorCode = AVERROR(EINVAL);
            return 0;
        }
        const double presentationTime = BetterTGFFmpegPlaybackFrameTime(
            job->videoFrame,
            job->videoTimeBase,
            job->videoDecodedTo
        );
        const double frameDuration = job->videoFrame->duration > 0
            ? (double)job->videoFrame->duration * av_q2d(job->videoTimeBase)
            : (job->videoFrameRate > 0.0 ? 1.0 / job->videoFrameRate : 1.0 / 30.0);
        const double frameEnd = presentationTime + fmax(0.0, frameDuration);
        job->videoDecodedTo = fmax(job->videoDecodedTo, frameEnd);
        const double callbackTime = fmax(presentationTime, seekTime);
        const double callbackEnd = fmin(frameEnd, targetTime);
        if (callbackEnd > callbackTime) {
            job->videoFrameCount += 1;
            if (job->videoCallback != NULL &&
                job->videoCallback(
                    job->context,
                    output,
                    width,
                    height,
                    (int)bytesPerRow,
                    callbackTime,
                    callbackEnd - callbackTime,
                    (job->videoFrame->flags & AV_FRAME_FLAG_KEY) != 0
                ) == 0) {
                av_free(output);
                job->errorCode = AVERROR_EXIT;
                return BetterTGFFmpegPlaybackIsCancelled(job) ? -1 : 0;
            }
        }
        av_free(output);
    }
}

static int BetterTGFFmpegPlaybackEmitAudio(
    BetterTGFFmpegPlaybackJob *job,
    const float *samples,
    int outputFrames,
    double presentationTime,
    double seekTime,
    double targetTime
) {
    if (outputFrames <= 0 || samples == NULL) {
        return 1;
    }
    const double frameDuration = (double)outputFrames / BETTERTG_PLAYBACK_AUDIO_SAMPLE_RATE;
    const double frameEnd = presentationTime + frameDuration;
    if (frameEnd <= seekTime || presentationTime >= targetTime) {
        return 1;
    }

    int startFrame = 0;
    if (presentationTime < seekTime) {
        const double skipped = ceil(
            (seekTime - presentationTime) * BETTERTG_PLAYBACK_AUDIO_SAMPLE_RATE
        );
        if (!isfinite(skipped) || skipped >= outputFrames) {
            return 1;
        }
        startFrame = skipped > 0.0 ? (int)skipped : 0;
    }

    int endFrame = outputFrames;
    if (frameEnd > targetTime) {
        const double retained = ceil(
            (targetTime - presentationTime) * BETTERTG_PLAYBACK_AUDIO_SAMPLE_RATE
        );
        if (!isfinite(retained) || retained <= 0.0) {
            return 1;
        }
        endFrame = retained < outputFrames ? (int)retained : outputFrames;
    }
    if (endFrame <= startFrame) {
        return 1;
    }

    const int callbackFrameCount = endFrame - startFrame;
    const double callbackTime = fmax(
        seekTime,
        presentationTime + (double)startFrame / BETTERTG_PLAYBACK_AUDIO_SAMPLE_RATE
    );
    job->audioFrameCount += 1;
    if (job->audioCallback != NULL &&
        job->audioCallback(
            job->context,
            samples + (size_t)startFrame * job->outputAudioChannels,
            callbackFrameCount,
            job->outputAudioChannels,
            BETTERTG_PLAYBACK_AUDIO_SAMPLE_RATE,
            callbackTime
        ) == 0) {
        job->errorCode = AVERROR_EXIT;
        return BetterTGFFmpegPlaybackIsCancelled(job) ? -1 : 0;
    }
    return 1;
}

static int BetterTGFFmpegPlaybackDrainAudio(
    BetterTGFFmpegPlaybackJob *job,
    double seekTime,
    double targetTime
) {
    if (job->audioCodecContext == NULL || job->audioFrame == NULL ||
        job->resampleContext == NULL) {
        return 1;
    }
    for (;;) {
        if (BetterTGFFmpegPlaybackIsCancelled(job)) {
            return -1;
        }
        av_frame_unref(job->audioFrame);
        const int result = avcodec_receive_frame(job->audioCodecContext, job->audioFrame);
        if (result == AVERROR(EAGAIN) || result == AVERROR_EOF) {
            return 1;
        }
        if (result < 0) {
            job->errorCode = result;
            return 0;
        }

        const int inputRate = job->audioCodecContext->sample_rate;
        if (inputRate <= 0 || job->audioFrame->nb_samples <= 0) {
            job->errorCode = AVERROR(EINVAL);
            return 0;
        }
        const int64_t outputCapacity64 = av_rescale_rnd(
            swr_get_delay(job->resampleContext, inputRate) + job->audioFrame->nb_samples,
            BETTERTG_PLAYBACK_AUDIO_SAMPLE_RATE,
            inputRate,
            AV_ROUND_UP
        );
        if (outputCapacity64 <= 0 || outputCapacity64 > 1000000) {
            job->errorCode = AVERROR(EINVAL);
            return 0;
        }
        const int outputCapacity = (int)outputCapacity64;
        uint8_t **outputData = NULL;
        int outputLineSize = 0;
        int allocationResult = av_samples_alloc_array_and_samples(
            &outputData,
            &outputLineSize,
            job->outputAudioChannels,
            outputCapacity,
            AV_SAMPLE_FMT_FLT,
            0
        );
        if (allocationResult < 0) {
            if (outputData != NULL) {
                av_freep(&outputData[0]);
                av_freep(&outputData);
            }
            job->errorCode = allocationResult;
            return 0;
        }
        const int outputFrames = swr_convert(
            job->resampleContext,
            outputData,
            outputCapacity,
            (const uint8_t **)job->audioFrame->extended_data,
            job->audioFrame->nb_samples
        );
        if (outputFrames < 0) {
            av_freep(&outputData[0]);
            av_freep(&outputData);
            job->errorCode = outputFrames;
            return 0;
        }
        const double presentationTime = BetterTGFFmpegPlaybackFrameTime(
            job->audioFrame,
            job->audioTimeBase,
            job->nextAudioTime
        );
        const double frameDuration = (double)outputFrames / BETTERTG_PLAYBACK_AUDIO_SAMPLE_RATE;
        const double frameEnd = presentationTime + frameDuration;
        job->nextAudioTime = frameEnd;
        job->audioDecodedTo = fmax(job->audioDecodedTo, frameEnd);
        const int emitResult = BetterTGFFmpegPlaybackEmitAudio(
            job,
            (const float *)outputData[0],
            outputFrames,
            presentationTime,
            seekTime,
            targetTime
        );
        av_freep(&outputData[0]);
        av_freep(&outputData);
        if (emitResult <= 0) {
            return emitResult;
        }
    }
}

static int BetterTGFFmpegPlaybackDrainResampler(
    BetterTGFFmpegPlaybackJob *job,
    double seekTime,
    double targetTime
) {
    if (job->resampleContext == NULL || job->audioCodecContext == NULL) {
        return 1;
    }
    const int inputRate = job->audioCodecContext->sample_rate;
    if (inputRate <= 0) {
        job->errorCode = AVERROR(EINVAL);
        return 0;
    }
    for (;;) {
        if (BetterTGFFmpegPlaybackIsCancelled(job)) {
            return -1;
        }
        const int64_t delayedSamples = swr_get_delay(job->resampleContext, inputRate);
        if (delayedSamples <= 0) {
            return 1;
        }
        const int64_t outputCapacity64 = av_rescale_rnd(
            delayedSamples,
            BETTERTG_PLAYBACK_AUDIO_SAMPLE_RATE,
            inputRate,
            AV_ROUND_UP
        );
        if (outputCapacity64 <= 0 || outputCapacity64 > 1000000) {
            job->errorCode = AVERROR(EINVAL);
            return 0;
        }
        const int outputCapacity = (int)outputCapacity64;
        uint8_t **outputData = NULL;
        int outputLineSize = 0;
        const int allocationResult = av_samples_alloc_array_and_samples(
            &outputData,
            &outputLineSize,
            job->outputAudioChannels,
            outputCapacity,
            AV_SAMPLE_FMT_FLT,
            0
        );
        if (allocationResult < 0) {
            if (outputData != NULL) {
                av_freep(&outputData[0]);
                av_freep(&outputData);
            }
            job->errorCode = allocationResult;
            return 0;
        }
        const int outputFrames = swr_convert(
            job->resampleContext,
            outputData,
            outputCapacity,
            NULL,
            0
        );
        if (outputFrames < 0) {
            av_freep(&outputData[0]);
            av_freep(&outputData);
            job->errorCode = outputFrames;
            return 0;
        }
        if (outputFrames == 0) {
            av_freep(&outputData[0]);
            av_freep(&outputData);
            return 1;
        }
        const double presentationTime = job->nextAudioTime;
        const double frameDuration = (double)outputFrames / BETTERTG_PLAYBACK_AUDIO_SAMPLE_RATE;
        const double frameEnd = presentationTime + frameDuration;
        job->nextAudioTime = frameEnd;
        job->audioDecodedTo = fmax(job->audioDecodedTo, frameEnd);
        const int emitResult = BetterTGFFmpegPlaybackEmitAudio(
            job,
            (const float *)outputData[0],
            outputFrames,
            presentationTime,
            seekTime,
            targetTime
        );
        av_freep(&outputData[0]);
        av_freep(&outputData);
        if (emitResult <= 0) {
            return emitResult;
        }
    }
}

static int BetterTGFFmpegPlaybackSendPacket(
    BetterTGFFmpegPlaybackJob *job,
    AVCodecContext *codecContext,
    AVPacket *packet,
    int isVideo,
    double seekTime,
    double targetTime
) {
    if (codecContext == NULL) {
        return 1;
    }
    int result = avcodec_send_packet(codecContext, packet);
    if (result == AVERROR(EAGAIN)) {
        result = isVideo
            ? BetterTGFFmpegPlaybackDrainVideo(job, seekTime, targetTime)
            : BetterTGFFmpegPlaybackDrainAudio(job, seekTime, targetTime);
        if (result <= 0) {
            return result;
        }
        result = avcodec_send_packet(codecContext, packet);
    }
    if (result < 0 && result != AVERROR_EOF) {
        job->errorCode = result;
        return 0;
    }
    return isVideo
        ? BetterTGFFmpegPlaybackDrainVideo(job, seekTime, targetTime)
        : BetterTGFFmpegPlaybackDrainAudio(job, seekTime, targetTime);
}

BetterTGFFmpegPlaybackJob *BetterTGFFmpegPlaybackJobCreate(
    void *context,
    int64_t fileSize,
    BetterTGFFmpegRangeReadCallback readCallback,
    BetterTGFFmpegVideoFrameCallback videoCallback,
    BetterTGFFmpegAudioFrameCallback audioCallback
) {
    if (context == NULL || fileSize <= 0 || readCallback == NULL) {
        return NULL;
    }
    BetterTGFFmpegPlaybackJob *job = calloc(1, sizeof(BetterTGFFmpegPlaybackJob));
    if (job == NULL) {
        return NULL;
    }
    job->context = context;
    job->fileSize = fileSize;
    job->readCallback = readCallback;
    job->videoCallback = videoCallback;
    job->audioCallback = audioCallback;
    job->videoStreamIndex = -1;
    job->audioStreamIndex = -1;
    atomic_init(&job->cancelled, 0);
    return job;
}

void BetterTGFFmpegPlaybackJobCancel(BetterTGFFmpegPlaybackJob *job) {
    if (job != NULL) {
        atomic_store_explicit(&job->cancelled, 1, memory_order_relaxed);
    }
}

int BetterTGFFmpegPlaybackJobRun(
    BetterTGFFmpegPlaybackJob *job,
    double seekTime,
    double decodeDuration
) {
    const double maximumSeekTime = (double)(INT64_MAX - 61000000LL) / AV_TIME_BASE;
    if (job == NULL || !isfinite(seekTime) || seekTime < 0.0 ||
        seekTime > maximumSeekTime || !isfinite(decodeDuration) ||
        decodeDuration <= 0.0 || decodeDuration > 60.0 ||
        !isfinite(seekTime + decodeDuration) || seekTime + decodeDuration > maximumSeekTime) {
        return 0;
    }
    if (BetterTGFFmpegPlaybackIsCancelled(job)) {
        return -1;
    }
    int result = BetterTGFFmpegPlaybackOpen(job);
    if (result < 0) {
        job->errorCode = result;
        return BetterTGFFmpegPlaybackIsCancelled(job) ? -1 : 0;
    }
    const double targetTime = seekTime + decodeDuration;
    job->videoDecodedTo = seekTime;
    job->audioDecodedTo = seekTime;
    job->nextAudioTime = seekTime;

    if (seekTime > 0.0) {
        const int64_t seekTimestamp = (int64_t)llround(seekTime * AV_TIME_BASE);
        result = avformat_seek_file(
            job->formatContext,
            -1,
            INT64_MIN,
            seekTimestamp,
            INT64_MAX,
            AVSEEK_FLAG_BACKWARD
        );
        if (result < 0) {
            job->errorCode = result;
            return BetterTGFFmpegPlaybackIsCancelled(job) ? -1 : 0;
        }
        if (job->videoCodecContext != NULL) {
            avcodec_flush_buffers(job->videoCodecContext);
        }
        if (job->audioCodecContext != NULL) {
            avcodec_flush_buffers(job->audioCodecContext);
        }
    }

    int packetCount = 0;
    while (!BetterTGFFmpegPlaybackIsCancelled(job) &&
           packetCount < BETTERTG_PLAYBACK_MAXIMUM_PACKET_COUNT) {
        const int videoDone = job->videoStreamIndex < 0 || job->videoDecodedTo >= targetTime;
        const int audioDone = job->audioStreamIndex < 0 || job->audioDecodedTo >= targetTime;
        if (videoDone && audioDone) {
            break;
        }
        av_packet_unref(job->packet);
        result = av_read_frame(job->formatContext, job->packet);
        if (result < 0) {
            if (result == AVERROR_EOF) {
                job->ended = 1;
                result = BetterTGFFmpegPlaybackSendPacket(
                    job,
                    job->videoCodecContext,
                    NULL,
                    1,
                    seekTime,
                    targetTime
                );
                if (result > 0) {
                    result = BetterTGFFmpegPlaybackSendPacket(
                        job,
                        job->audioCodecContext,
                        NULL,
                        0,
                        seekTime,
                        targetTime
                    );
                }
                if (result > 0) {
                    result = BetterTGFFmpegPlaybackDrainResampler(job, seekTime, targetTime);
                }
                if (result <= 0) {
                    return result;
                }
                break;
            }
            job->errorCode = result;
            return BetterTGFFmpegPlaybackIsCancelled(job) ? -1 : 0;
        }
        packetCount += 1;
        if (job->packet->stream_index == job->videoStreamIndex) {
            result = job->videoDecodedTo >= targetTime
                ? 1
                : BetterTGFFmpegPlaybackSendPacket(
                    job,
                    job->videoCodecContext,
                    job->packet,
                    1,
                    seekTime,
                    targetTime
                );
        } else if (job->packet->stream_index == job->audioStreamIndex) {
            result = job->audioDecodedTo >= targetTime
                ? 1
                : BetterTGFFmpegPlaybackSendPacket(
                    job,
                    job->audioCodecContext,
                    job->packet,
                    0,
                    seekTime,
                    targetTime
                );
        } else {
            result = 1;
        }
        if (result <= 0) {
            av_packet_unref(job->packet);
            return result;
        }
    }
    av_packet_unref(job->packet);
    if (BetterTGFFmpegPlaybackIsCancelled(job)) {
        return -1;
    }
    if (packetCount >= BETTERTG_PLAYBACK_MAXIMUM_PACKET_COUNT) {
        job->errorCode = AVERROR(EFBIG);
        return 0;
    }
    return 1;
}

void BetterTGFFmpegPlaybackJobDestroy(BetterTGFFmpegPlaybackJob *job) {
    if (job == NULL) {
        return;
    }
    BetterTGFFmpegPlaybackJobCancel(job);
    BetterTGFFmpegPlaybackClose(job);
    free(job);
}

int BetterTGFFmpegPlaybackJobHasAudio(const BetterTGFFmpegPlaybackJob *job) {
    return job != NULL && job->audioStreamIndex >= 0;
}

int BetterTGFFmpegPlaybackJobHasVideo(const BetterTGFFmpegPlaybackJob *job) {
    return job != NULL && job->videoStreamIndex >= 0;
}

int BetterTGFFmpegPlaybackJobIsEnded(const BetterTGFFmpegPlaybackJob *job) {
    return job != NULL ? job->ended : 0;
}

int BetterTGFFmpegPlaybackJobVideoCodecID(const BetterTGFFmpegPlaybackJob *job) {
    return job != NULL && job->videoCodecContext != NULL ? job->videoCodecContext->codec_id : 0;
}

int BetterTGFFmpegPlaybackJobAudioCodecID(const BetterTGFFmpegPlaybackJob *job) {
    return job != NULL && job->audioCodecContext != NULL ? job->audioCodecContext->codec_id : 0;
}

int BetterTGFFmpegPlaybackJobVideoIsVP9(const BetterTGFFmpegPlaybackJob *job) {
    return job != NULL && job->videoCodecContext != NULL &&
        job->videoCodecContext->codec_id == AV_CODEC_ID_VP9;
}

int BetterTGFFmpegPlaybackJobAudioIsOpus(const BetterTGFFmpegPlaybackJob *job) {
    return job != NULL && job->audioCodecContext != NULL &&
        job->audioCodecContext->codec_id == AV_CODEC_ID_OPUS;
}

int BetterTGFFmpegPlaybackJobVideoFrameCount(const BetterTGFFmpegPlaybackJob *job) {
    return job != NULL ? job->videoFrameCount : 0;
}

int BetterTGFFmpegPlaybackJobAudioFrameCount(const BetterTGFFmpegPlaybackJob *job) {
    return job != NULL ? job->audioFrameCount : 0;
}

double BetterTGFFmpegPlaybackJobVideoDecodedTo(const BetterTGFFmpegPlaybackJob *job) {
    return job != NULL ? job->videoDecodedTo : 0.0;
}

double BetterTGFFmpegPlaybackJobAudioDecodedTo(const BetterTGFFmpegPlaybackJob *job) {
    return job != NULL ? job->audioDecodedTo : 0.0;
}

double BetterTGFFmpegPlaybackJobDuration(const BetterTGFFmpegPlaybackJob *job) {
    return job != NULL ? job->duration : 0.0;
}

int64_t BetterTGFFmpegPlaybackJobBytesRead(const BetterTGFFmpegPlaybackJob *job) {
    return job != NULL ? job->bytesRead : 0;
}

int BetterTGFFmpegPlaybackJobReadCallCount(const BetterTGFFmpegPlaybackJob *job) {
    return job != NULL ? job->readCallCount : 0;
}

int BetterTGFFmpegPlaybackJobSeekCallCount(const BetterTGFFmpegPlaybackJob *job) {
    return job != NULL ? job->seekCallCount : 0;
}

int BetterTGFFmpegPlaybackJobSizeCallCount(const BetterTGFFmpegPlaybackJob *job) {
    return job != NULL ? job->sizeCallCount : 0;
}

int BetterTGFFmpegPlaybackJobErrorCode(const BetterTGFFmpegPlaybackJob *job) {
    return job != NULL ? job->errorCode : AVERROR(EINVAL);
}
