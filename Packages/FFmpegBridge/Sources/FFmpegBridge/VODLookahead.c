#include "FFmpegBridge.h"

#include <libavformat/avio.h>
#include <libavutil/mathematics.h>
#include <libavutil/parseutils.h>

#include <errno.h>
#include <limits.h>
#include <math.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define BETTERTG_AVIO_BUFFER_SIZE (64 * 1024)
#define BETTERTG_MAXIMUM_READ_SIZE (256 * 1024)
#define BETTERTG_MAXIMUM_READ_CALLS 100000
#define BETTERTG_MAXIMUM_PACKET_COUNT 1000000
#define BETTERTG_MINIMUM_READ_BUDGET (16LL * 1024 * 1024)
#define BETTERTG_MAXIMUM_READ_BUDGET (512LL * 1024 * 1024)

struct BetterTGFFmpegLookaheadJob {
    void *context;
    BetterTGFFmpegRangeReadCallback readCallback;
    int64_t fileSize;
    int64_t readingOffset;
    int64_t maximumBytesRead;
    atomic_int cancelled;

    AVFormatContext *formatContext;
    AVIOContext *ioContext;
    int audioStreamIndex;
    int videoStreamIndex;
    double audioReadableTo;
    double videoReadableTo;
    double duration;
    double timelineOrigin;
    double audioEndTime;
    double videoEndTime;
    double audioStartTime;
    double videoStartTime;
    int ended;
    int64_t bytesRead;
    int readCallCount;
    int seekCallCount;
    int sizeCallCount;
    int errorCode;
};

static int BetterTGFFmpegLookaheadIsCancelled(
    const BetterTGFFmpegLookaheadJob *job
) {
    return job == NULL || atomic_load_explicit(&job->cancelled, memory_order_relaxed) != 0;
}

static int BetterTGFFmpegLookaheadInterrupt(void *opaque) {
    return BetterTGFFmpegLookaheadIsCancelled((BetterTGFFmpegLookaheadJob *)opaque);
}

static int BetterTGFFmpegLookaheadRead(
    void *opaque,
    uint8_t *destination,
    int destinationCapacity
) {
    BetterTGFFmpegLookaheadJob *job = opaque;
    if (job == NULL || destination == NULL || destinationCapacity <= 0 ||
        job->readCallback == NULL) {
        return AVERROR(EINVAL);
    }
    if (BetterTGFFmpegLookaheadIsCancelled(job)) {
        return AVERROR_EXIT;
    }
    if (job->readingOffset >= job->fileSize) {
        return AVERROR_EOF;
    }
    if (job->readCallCount >= BETTERTG_MAXIMUM_READ_CALLS ||
        job->bytesRead >= job->maximumBytesRead) {
        return AVERROR(EFBIG);
    }

    const int64_t remaining = job->fileSize - job->readingOffset;
    int readCapacity = destinationCapacity;
    if (readCapacity > BETTERTG_MAXIMUM_READ_SIZE) {
        readCapacity = BETTERTG_MAXIMUM_READ_SIZE;
    }
    if ((int64_t)readCapacity > remaining) {
        readCapacity = (int)remaining;
    }
    const int64_t budgetRemaining = job->maximumBytesRead - job->bytesRead;
    if ((int64_t)readCapacity > budgetRemaining) {
        readCapacity = (int)budgetRemaining;
    }
    if (readCapacity <= 0) {
        return AVERROR_EOF;
    }

    job->readCallCount += 1;
    const int result = job->readCallback(
        job->context,
        job->readingOffset,
        destination,
        readCapacity
    );
    if (result > readCapacity) {
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

static int BetterTGFFmpegCheckedAdd(int64_t left, int64_t right, int64_t *result) {
    if ((right > 0 && left > INT64_MAX - right) ||
        (right < 0 && left < INT64_MIN - right)) {
        return 0;
    }
    *result = left + right;
    return 1;
}

static int64_t BetterTGFFmpegLookaheadSeek(
    void *opaque,
    int64_t offset,
    int whence
) {
    BetterTGFFmpegLookaheadJob *job = opaque;
    if (job == NULL) {
        return AVERROR(EINVAL);
    }
    if ((whence & AVSEEK_SIZE) != 0) {
        job->sizeCallCount += 1;
        return job->fileSize;
    }
    if (BetterTGFFmpegLookaheadIsCancelled(job)) {
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
    if (!BetterTGFFmpegCheckedAdd(base, offset, &target) ||
        target < 0 || target > job->fileSize) {
        return AVERROR(EINVAL);
    }
    job->readingOffset = target;
    job->seekCallCount += 1;
    return target;
}

static void BetterTGFFmpegLookaheadClose(BetterTGFFmpegLookaheadJob *job) {
    if (job == NULL) {
        return;
    }
    avformat_close_input(&job->formatContext);
    if (job->ioContext != NULL) {
        av_freep(&job->ioContext->buffer);
    }
    avio_context_free(&job->ioContext);
}

static int BetterTGFFmpegLookaheadOpen(BetterTGFFmpegLookaheadJob *job) {
    uint8_t *buffer = av_malloc(BETTERTG_AVIO_BUFFER_SIZE);
    if (buffer == NULL) {
        return AVERROR(ENOMEM);
    }
    job->ioContext = avio_alloc_context(
        buffer,
        BETTERTG_AVIO_BUFFER_SIZE,
        0,
        job,
        BetterTGFFmpegLookaheadRead,
        NULL,
        BetterTGFFmpegLookaheadSeek
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
    job->formatContext->flags |= AVFMT_FLAG_CUSTOM_IO | AVFMT_FLAG_FAST_SEEK | AVFMT_FLAG_NOBUFFER;
    job->formatContext->interrupt_callback.callback = BetterTGFFmpegLookaheadInterrupt;
    job->formatContext->interrupt_callback.opaque = job;

    AVDictionary *options = NULL;
    av_dict_set(&options, "usetoc", "1", 0);
    int result = avformat_open_input(&job->formatContext, NULL, NULL, &options);
    av_dict_free(&options);
    if (result < 0) {
        return result;
    }
    return avformat_find_stream_info(job->formatContext, NULL);
}

static int BetterTGFFmpegLookaheadFindStream(
    const BetterTGFFmpegLookaheadJob *job,
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

static double BetterTGFFmpegLookaheadStreamDuration(const AVStream *stream) {
    if (stream == NULL || stream->duration == AV_NOPTS_VALUE ||
        stream->time_base.num <= 0 || stream->time_base.den <= 0) {
        return 0.0;
    }
    const double duration = (double)stream->duration * av_q2d(stream->time_base);
    return fmax(0.0, duration);
}

static double BetterTGFFmpegLookaheadStreamStart(const AVStream *stream) {
    if (stream == NULL || stream->start_time == AV_NOPTS_VALUE ||
        stream->time_base.num <= 0 || stream->time_base.den <= 0) {
        return NAN;
    }
    const double value = (double)stream->start_time * av_q2d(stream->time_base);
    return isfinite(value) ? value : NAN;
}

static double BetterTGFFmpegLookaheadNormalizedStreamEnd(
    const AVStream *stream,
    double timelineOrigin,
    double fallbackDuration
) {
    const double rawStart = BetterTGFFmpegLookaheadStreamStart(stream);
    const double start = isfinite(rawStart) ? rawStart - timelineOrigin : 0.0;
    const double duration = BetterTGFFmpegLookaheadStreamDuration(stream);
    if (duration > 0.0) {
        return fmax(0.0, start + duration);
    }
    const AVDictionaryEntry *durationEntry = stream != NULL
        ? av_dict_get(stream->metadata, "DURATION", NULL, 0)
        : NULL;
    int64_t taggedEnd = 0;
    if (durationEntry != NULL && durationEntry->value != NULL &&
        av_parse_time(&taggedEnd, durationEntry->value, 1) >= 0) {
        const double end = (double)taggedEnd / AV_TIME_BASE - timelineOrigin;
        if (isfinite(end) && end >= start) {
            return fmax(0.0, end);
        }
    }
    return fmax(fmax(0.0, start), fallbackDuration);
}

static double BetterTGFFmpegLookaheadPacketEnd(
    const AVStream *stream,
    const AVPacket *packet,
    double timelineOrigin
) {
    if (stream == NULL || stream->time_base.num <= 0 || stream->time_base.den <= 0) {
        return -1.0;
    }
    int64_t timestamp = packet->pts;
    if (timestamp == AV_NOPTS_VALUE) {
        timestamp = packet->dts;
    }
    if (timestamp == AV_NOPTS_VALUE) {
        return -1.0;
    }
    const double packetStart = (double)timestamp * av_q2d(stream->time_base);
    const double packetDuration = packet->duration > 0
        ? (double)packet->duration * av_q2d(stream->time_base)
        : 0.0;
    return fmax(0.0, packetStart + packetDuration - timelineOrigin);
}

BetterTGFFmpegLookaheadJob *BetterTGFFmpegLookaheadJobCreate(
    void *context,
    int64_t fileSize,
    BetterTGFFmpegRangeReadCallback readCallback
) {
    if (context == NULL || fileSize <= 0 || readCallback == NULL) {
        return NULL;
    }
    BetterTGFFmpegLookaheadJob *job = calloc(1, sizeof(BetterTGFFmpegLookaheadJob));
    if (job == NULL) {
        return NULL;
    }
    job->context = context;
    job->fileSize = fileSize;
    job->readCallback = readCallback;
    if (fileSize > BETTERTG_MAXIMUM_READ_BUDGET / 8) {
        job->maximumBytesRead = BETTERTG_MAXIMUM_READ_BUDGET;
    } else {
        const int64_t scaledBudget = fileSize * 8;
        job->maximumBytesRead = scaledBudget > BETTERTG_MINIMUM_READ_BUDGET
            ? scaledBudget
            : BETTERTG_MINIMUM_READ_BUDGET;
    }
    job->audioStreamIndex = -1;
    job->videoStreamIndex = -1;
    job->audioReadableTo = -1.0;
    job->videoReadableTo = -1.0;
    atomic_init(&job->cancelled, 0);
    return job;
}

void BetterTGFFmpegLookaheadJobCancel(BetterTGFFmpegLookaheadJob *job) {
    if (job != NULL) {
        atomic_store_explicit(&job->cancelled, 1, memory_order_relaxed);
    }
}

int BetterTGFFmpegLookaheadJobRun(
    BetterTGFFmpegLookaheadJob *job,
    double seekTime,
    double lookaheadDuration
) {
    if (job == NULL || !isfinite(seekTime) || !isfinite(lookaheadDuration) ||
        seekTime < 0.0 || lookaheadDuration < 0.0) {
        return 0;
    }
    if (BetterTGFFmpegLookaheadIsCancelled(job)) {
        return -1;
    }

    int result = BetterTGFFmpegLookaheadOpen(job);
    if (result < 0) {
        job->errorCode = result;
        BetterTGFFmpegLookaheadClose(job);
        return BetterTGFFmpegLookaheadIsCancelled(job) ? -1 : 0;
    }

    job->audioStreamIndex = BetterTGFFmpegLookaheadFindStream(job, AVMEDIA_TYPE_AUDIO);
    job->videoStreamIndex = BetterTGFFmpegLookaheadFindStream(job, AVMEDIA_TYPE_VIDEO);
    if (job->audioStreamIndex < 0 && job->videoStreamIndex < 0) {
        job->errorCode = AVERROR_STREAM_NOT_FOUND;
        BetterTGFFmpegLookaheadClose(job);
        return 0;
    }

    double timelineOrigin = NAN;
    if (job->videoStreamIndex >= 0) {
        timelineOrigin = BetterTGFFmpegLookaheadStreamStart(
            job->formatContext->streams[job->videoStreamIndex]
        );
    }
    if (!isfinite(timelineOrigin) && job->formatContext->start_time != AV_NOPTS_VALUE) {
        timelineOrigin = (double)job->formatContext->start_time / AV_TIME_BASE;
    }
    if (!isfinite(timelineOrigin) && job->audioStreamIndex >= 0) {
        timelineOrigin = BetterTGFFmpegLookaheadStreamStart(
            job->formatContext->streams[job->audioStreamIndex]
        );
    }
    job->timelineOrigin = isfinite(timelineOrigin) ? timelineOrigin : 0.0;

    if (job->formatContext->duration != AV_NOPTS_VALUE) {
        const double formatDuration = (double)job->formatContext->duration / AV_TIME_BASE;
        if (isfinite(formatDuration) && formatDuration > 0.0) {
            job->duration = job->timelineOrigin > 0.0 && formatDuration > job->timelineOrigin
                ? formatDuration - job->timelineOrigin
                : formatDuration;
        }
    }
    if (job->audioStreamIndex >= 0) {
        job->duration = fmax(
            job->duration,
            BetterTGFFmpegLookaheadStreamDuration(
                job->formatContext->streams[job->audioStreamIndex]
            )
        );
    }
    if (job->videoStreamIndex >= 0) {
        job->duration = fmax(
            job->duration,
            BetterTGFFmpegLookaheadStreamDuration(
                job->formatContext->streams[job->videoStreamIndex]
            )
        );
    }
    if (job->audioStreamIndex >= 0) {
        const double rawStart = BetterTGFFmpegLookaheadStreamStart(
            job->formatContext->streams[job->audioStreamIndex]
        );
        job->audioStartTime = isfinite(rawStart)
            ? fmax(0.0, rawStart - job->timelineOrigin)
            : 0.0;
        job->audioEndTime = BetterTGFFmpegLookaheadNormalizedStreamEnd(
            job->formatContext->streams[job->audioStreamIndex],
            job->timelineOrigin,
            job->duration
        );
    }
    if (job->videoStreamIndex >= 0) {
        const double rawStart = BetterTGFFmpegLookaheadStreamStart(
            job->formatContext->streams[job->videoStreamIndex]
        );
        job->videoStartTime = isfinite(rawStart)
            ? fmax(0.0, rawStart - job->timelineOrigin)
            : 0.0;
        job->videoEndTime = BetterTGFFmpegLookaheadNormalizedStreamEnd(
            job->formatContext->streams[job->videoStreamIndex],
            job->timelineOrigin,
            job->duration
        );
    }
    const double normalizedDuration = fmax(job->videoEndTime, job->audioEndTime);
    if (normalizedDuration > 0.0) {
        job->duration = normalizedDuration;
    }
    if (job->duration > 0.0 && seekTime > job->duration) {
        seekTime = job->duration;
    }

    const int preferredStreamIndex = job->videoStreamIndex >= 0
        ? job->videoStreamIndex
        : job->audioStreamIndex;
    const AVStream *preferredStream = job->formatContext->streams[preferredStreamIndex];
    if (preferredStream->time_base.num <= 0 || preferredStream->time_base.den <= 0 ||
        seekTime > (double)INT64_MAX / AV_TIME_BASE) {
        job->errorCode = AVERROR(EINVAL);
        BetterTGFFmpegLookaheadClose(job);
        return 0;
    }
    const double absoluteSeekTime = seekTime + job->timelineOrigin;
    if (!isfinite(absoluteSeekTime) ||
        absoluteSeekTime <= (double)INT64_MIN / AV_TIME_BASE ||
        absoluteSeekTime >= (double)INT64_MAX / AV_TIME_BASE) {
        job->errorCode = AVERROR(EINVAL);
        BetterTGFFmpegLookaheadClose(job);
        return 0;
    }
    const double seekMicroseconds = absoluteSeekTime * AV_TIME_BASE;
    if (!isfinite(seekMicroseconds) ||
        seekMicroseconds <= (double)INT64_MIN ||
        seekMicroseconds >= (double)INT64_MAX) {
        job->errorCode = AVERROR(EINVAL);
        BetterTGFFmpegLookaheadClose(job);
        return 0;
    }
    const int64_t seekTimestamp = av_rescale_q(
        (int64_t)llround(seekMicroseconds),
        AV_TIME_BASE_Q,
        preferredStream->time_base
    );
    result = av_seek_frame(
        job->formatContext,
        preferredStreamIndex,
        seekTimestamp,
        AVSEEK_FLAG_BACKWARD
    );
    if (result < 0) {
        job->errorCode = result;
        BetterTGFFmpegLookaheadClose(job);
        return BetterTGFFmpegLookaheadIsCancelled(job) ? -1 : 0;
    }
    avformat_flush(job->formatContext);

    AVPacket *packet = av_packet_alloc();
    if (packet == NULL) {
        job->errorCode = AVERROR(ENOMEM);
        BetterTGFFmpegLookaheadClose(job);
        return 0;
    }

    const double targetTime = seekTime + lookaheadDuration;
    if (!isfinite(targetTime) || targetTime < seekTime) {
        job->errorCode = AVERROR(EINVAL);
        av_packet_free(&packet);
        BetterTGFFmpegLookaheadClose(job);
        return 0;
    }
    int packetCount = 0;
    for (;;) {
        const int audioRequired = job->audioStreamIndex >= 0 &&
            targetTime > job->audioStartTime &&
            (job->audioEndTime <= 0.0 || seekTime < job->audioEndTime);
        const int videoRequired = job->videoStreamIndex >= 0 &&
            targetTime > job->videoStartTime &&
            (job->videoEndTime <= 0.0 || seekTime < job->videoEndTime);
        const double audioTargetTime = job->audioEndTime > 0.0
            ? fmin(targetTime, job->audioEndTime)
            : targetTime;
        const double videoTargetTime = job->videoEndTime > 0.0
            ? fmin(targetTime, job->videoEndTime)
            : targetTime;
        const int audioReady = !audioRequired ||
            job->audioReadableTo >= audioTargetTime;
        const int videoReady = !videoRequired ||
            job->videoReadableTo >= videoTargetTime;
        if (audioReady && videoReady) {
            result = 1;
            break;
        }
        if (BetterTGFFmpegLookaheadIsCancelled(job)) {
            result = -1;
            break;
        }

        const int readResult = av_read_frame(job->formatContext, packet);
        if (readResult == AVERROR_EOF) {
            job->ended = 1;
            result = 1;
            break;
        }
        if (readResult < 0) {
            job->errorCode = readResult;
            result = BetterTGFFmpegLookaheadIsCancelled(job) || readResult == AVERROR_EXIT
                ? -1
                : 0;
            break;
        }
        packetCount += 1;
        if (packetCount > BETTERTG_MAXIMUM_PACKET_COUNT) {
            job->errorCode = AVERROR(ELOOP);
            result = 0;
            av_packet_unref(packet);
            break;
        }

        if (packet->stream_index == job->audioStreamIndex) {
            const double packetEnd = BetterTGFFmpegLookaheadPacketEnd(
                job->formatContext->streams[job->audioStreamIndex],
                packet,
                job->timelineOrigin
            );
            if (packetEnd >= 0.0) {
                job->audioReadableTo = fmax(job->audioReadableTo, packetEnd);
            }
        } else if (packet->stream_index == job->videoStreamIndex) {
            const double packetEnd = BetterTGFFmpegLookaheadPacketEnd(
                job->formatContext->streams[job->videoStreamIndex],
                packet,
                job->timelineOrigin
            );
            if (packetEnd >= 0.0) {
                job->videoReadableTo = fmax(job->videoReadableTo, packetEnd);
            }
        }
        av_packet_unref(packet);
    }

    av_packet_free(&packet);
    BetterTGFFmpegLookaheadClose(job);
    return result;
}

void BetterTGFFmpegLookaheadJobDestroy(BetterTGFFmpegLookaheadJob *job) {
    if (job == NULL) {
        return;
    }
    BetterTGFFmpegLookaheadJobCancel(job);
    BetterTGFFmpegLookaheadClose(job);
    free(job);
}

int BetterTGFFmpegLookaheadJobHasAudio(const BetterTGFFmpegLookaheadJob *job) {
    return job != NULL && job->audioStreamIndex >= 0;
}

int BetterTGFFmpegLookaheadJobHasVideo(const BetterTGFFmpegLookaheadJob *job) {
    return job != NULL && job->videoStreamIndex >= 0;
}

int BetterTGFFmpegLookaheadJobIsEnded(const BetterTGFFmpegLookaheadJob *job) {
    return job != NULL ? job->ended : 0;
}

double BetterTGFFmpegLookaheadJobAudioReadableTo(const BetterTGFFmpegLookaheadJob *job) {
    return job != NULL ? job->audioReadableTo : -1.0;
}

double BetterTGFFmpegLookaheadJobVideoReadableTo(const BetterTGFFmpegLookaheadJob *job) {
    return job != NULL ? job->videoReadableTo : -1.0;
}

double BetterTGFFmpegLookaheadJobDuration(const BetterTGFFmpegLookaheadJob *job) {
    return job != NULL ? job->duration : 0.0;
}

int64_t BetterTGFFmpegLookaheadJobBytesRead(const BetterTGFFmpegLookaheadJob *job) {
    return job != NULL ? job->bytesRead : 0;
}

int BetterTGFFmpegLookaheadJobReadCallCount(const BetterTGFFmpegLookaheadJob *job) {
    return job != NULL ? job->readCallCount : 0;
}

int BetterTGFFmpegLookaheadJobSeekCallCount(const BetterTGFFmpegLookaheadJob *job) {
    return job != NULL ? job->seekCallCount : 0;
}

int BetterTGFFmpegLookaheadJobSizeCallCount(const BetterTGFFmpegLookaheadJob *job) {
    return job != NULL ? job->sizeCallCount : 0;
}

int BetterTGFFmpegLookaheadJobErrorCode(const BetterTGFFmpegLookaheadJob *job) {
    return job != NULL ? job->errorCode : AVERROR(EINVAL);
}
