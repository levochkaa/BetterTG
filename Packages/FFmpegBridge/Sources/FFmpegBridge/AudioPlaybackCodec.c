#include "FFmpegBridge.h"

#include <libavutil/channel_layout.h>
#include <libavutil/mathematics.h>
#include <libavutil/samplefmt.h>

#include <errno.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct BetterTGFFmpegAudioDecodeJob {
    char *inputPath;
    char *outputPath;
    int64_t maximumOutputBytes;
    atomic_int cancelled;
};

static char *BetterTGFFmpegCopyString(const char *value) {
    if (value == NULL) {
        return NULL;
    }
    const size_t length = strlen(value) + 1;
    char *result = malloc(length);
    if (result != NULL) {
        memcpy(result, value, length);
    }
    return result;
}

static void BetterTGFFmpegWriteUInt16LE(uint8_t *destination, uint16_t value) {
    destination[0] = (uint8_t)(value & 0xFF);
    destination[1] = (uint8_t)((value >> 8) & 0xFF);
}

static void BetterTGFFmpegWriteUInt32LE(uint8_t *destination, uint32_t value) {
    destination[0] = (uint8_t)(value & 0xFF);
    destination[1] = (uint8_t)((value >> 8) & 0xFF);
    destination[2] = (uint8_t)((value >> 16) & 0xFF);
    destination[3] = (uint8_t)((value >> 24) & 0xFF);
}

static int BetterTGFFmpegWriteWAVHeader(
    FILE *file,
    int channels,
    int sampleRate,
    int64_t dataBytes
) {
    if (file == NULL || channels <= 0 || sampleRate <= 0 ||
        dataBytes < 0 || dataBytes > UINT32_MAX - 36) {
        return AVERROR(EINVAL);
    }
    uint8_t header[44] = {0};
    memcpy(header, "RIFF", 4);
    BetterTGFFmpegWriteUInt32LE(header + 4, (uint32_t)dataBytes + 36);
    memcpy(header + 8, "WAVEfmt ", 8);
    BetterTGFFmpegWriteUInt32LE(header + 16, 16);
    BetterTGFFmpegWriteUInt16LE(header + 20, 1);
    BetterTGFFmpegWriteUInt16LE(header + 22, (uint16_t)channels);
    BetterTGFFmpegWriteUInt32LE(header + 24, (uint32_t)sampleRate);
    BetterTGFFmpegWriteUInt32LE(header + 28, (uint32_t)(sampleRate * channels * 2));
    BetterTGFFmpegWriteUInt16LE(header + 32, (uint16_t)(channels * 2));
    BetterTGFFmpegWriteUInt16LE(header + 34, 16);
    memcpy(header + 36, "data", 4);
    BetterTGFFmpegWriteUInt32LE(header + 40, (uint32_t)dataBytes);
    if (fseek(file, 0, SEEK_SET) != 0 || fwrite(header, 1, sizeof(header), file) != sizeof(header)) {
        return AVERROR(errno != 0 ? errno : EIO);
    }
    return 0;
}

static int BetterTGFFmpegAudioDecodeJobIsCancelled(
    const BetterTGFFmpegAudioDecodeJob *job
) {
    return atomic_load_explicit(&job->cancelled, memory_order_relaxed) != 0;
}

static int BetterTGFFmpegWriteResampledAudio(
    BetterTGFFmpegAudioDecodeJob *job,
    SwrContext *resampler,
    const AVCodecContext *decoder,
    const AVFrame *frame,
    FILE *output,
    int outputChannels,
    int outputSampleRate,
    int64_t *outputBytes
) {
    if (BetterTGFFmpegAudioDecodeJobIsCancelled(job)) {
        return AVERROR_EXIT;
    }
    const int64_t delay = swr_get_delay(resampler, decoder->sample_rate);
    const int inputSamples = frame != NULL ? frame->nb_samples : 0;
    const int outputCapacity = frame != NULL
        ? (int)av_rescale_rnd(
            delay + inputSamples,
            outputSampleRate,
            decoder->sample_rate,
            AV_ROUND_UP
        )
        : swr_get_out_samples(resampler, 0);
    if (outputCapacity <= 0) {
        return outputCapacity;
    }
    uint8_t *outputData = NULL;
    int lineSize = 0;
    int result = av_samples_alloc(
        &outputData,
        &lineSize,
        outputChannels,
        outputCapacity,
        AV_SAMPLE_FMT_S16,
        0
    );
    if (result < 0) {
        return result;
    }
    const uint8_t **inputData = frame != NULL
        ? (const uint8_t **)frame->extended_data
        : NULL;
    const int convertedSamples = swr_convert(
        resampler,
        &outputData,
        outputCapacity,
        inputData,
        inputSamples
    );
    if (convertedSamples < 0) {
        result = convertedSamples;
    } else {
        const int64_t byteCount = (int64_t)convertedSamples * outputChannels * 2;
        if (*outputBytes + byteCount > job->maximumOutputBytes) {
            result = AVERROR(ENOSPC);
        } else if (byteCount > 0 &&
                   fwrite(outputData, 1, (size_t)byteCount, output) != (size_t)byteCount) {
            result = AVERROR(errno != 0 ? errno : EIO);
        } else {
            *outputBytes += byteCount;
            result = convertedSamples;
        }
    }
    av_freep(&outputData);
    return result;
}

static int BetterTGFFmpegDrainAudioDecoder(
    BetterTGFFmpegAudioDecodeJob *job,
    AVCodecContext *decoder,
    AVFrame *frame,
    SwrContext *resampler,
    FILE *output,
    int outputChannels,
    int outputSampleRate,
    int64_t *outputBytes
) {
    for (;;) {
        if (BetterTGFFmpegAudioDecodeJobIsCancelled(job)) {
            return AVERROR_EXIT;
        }
        int result = avcodec_receive_frame(decoder, frame);
        if (result == AVERROR(EAGAIN) || result == AVERROR_EOF) {
            return 0;
        }
        if (result < 0) {
            return result;
        }
        result = BetterTGFFmpegWriteResampledAudio(
            job,
            resampler,
            decoder,
            frame,
            output,
            outputChannels,
            outputSampleRate,
            outputBytes
        );
        av_frame_unref(frame);
        if (result < 0) {
            return result;
        }
    }
}

BetterTGFFmpegAudioDecodeJob *BetterTGFFmpegAudioDecodeJobCreate(
    const char *inputPath,
    const char *outputPath,
    int64_t maximumOutputBytes
) {
    if (inputPath == NULL || inputPath[0] == '\0' ||
        outputPath == NULL || outputPath[0] == '\0' || maximumOutputBytes <= 44) {
        return NULL;
    }
    BetterTGFFmpegAudioDecodeJob *job = calloc(1, sizeof(BetterTGFFmpegAudioDecodeJob));
    if (job == NULL) {
        return NULL;
    }
    job->inputPath = BetterTGFFmpegCopyString(inputPath);
    job->outputPath = BetterTGFFmpegCopyString(outputPath);
    job->maximumOutputBytes = maximumOutputBytes;
    atomic_init(&job->cancelled, 0);
    if (job->inputPath == NULL || job->outputPath == NULL) {
        BetterTGFFmpegAudioDecodeJobDestroy(job);
        return NULL;
    }
    return job;
}

void BetterTGFFmpegAudioDecodeJobCancel(BetterTGFFmpegAudioDecodeJob *job) {
    if (job != NULL) {
        atomic_store_explicit(&job->cancelled, 1, memory_order_relaxed);
    }
}

int BetterTGFFmpegAudioDecodeJobRun(BetterTGFFmpegAudioDecodeJob *job) {
    if (job == NULL || BetterTGFFmpegAudioDecodeJobIsCancelled(job)) {
        return AVERROR_EXIT;
    }
    AVFormatContext *format = NULL;
    AVCodecContext *decoder = NULL;
    SwrContext *resampler = NULL;
    AVFrame *frame = NULL;
    AVPacket *packet = NULL;
    FILE *output = NULL;
    AVChannelLayout outputLayout = {0};
    int streamIndex = -1;
    int result = AVERROR_UNKNOWN;
    int64_t outputBytes = 0;
    const int outputSampleRate = 48000;

    result = avformat_open_input(&format, job->inputPath, NULL, NULL);
    if (result < 0) {
        goto cleanup;
    }
    result = avformat_find_stream_info(format, NULL);
    if (result < 0) {
        goto cleanup;
    }
    const AVCodec *codec = NULL;
    streamIndex = av_find_best_stream(format, AVMEDIA_TYPE_AUDIO, -1, -1, &codec, 0);
    if (streamIndex < 0 || codec == NULL) {
        result = streamIndex < 0 ? streamIndex : AVERROR_DECODER_NOT_FOUND;
        goto cleanup;
    }
    decoder = avcodec_alloc_context3(codec);
    if (decoder == NULL) {
        result = AVERROR(ENOMEM);
        goto cleanup;
    }
    result = avcodec_parameters_to_context(decoder, format->streams[streamIndex]->codecpar);
    if (result < 0) {
        goto cleanup;
    }
    result = avcodec_open2(decoder, codec, NULL);
    if (result < 0 || decoder->sample_rate <= 0 || decoder->ch_layout.nb_channels <= 0) {
        result = result < 0 ? result : AVERROR(EINVAL);
        goto cleanup;
    }
    const int outputChannels = decoder->ch_layout.nb_channels == 1 ? 1 : 2;
    av_channel_layout_default(&outputLayout, outputChannels);
    result = swr_alloc_set_opts2(
        &resampler,
        &outputLayout,
        AV_SAMPLE_FMT_S16,
        outputSampleRate,
        &decoder->ch_layout,
        decoder->sample_fmt,
        decoder->sample_rate,
        0,
        NULL
    );
    if (result < 0 || resampler == NULL) {
        result = result < 0 ? result : AVERROR(ENOMEM);
        goto cleanup;
    }
    result = swr_init(resampler);
    if (result < 0) {
        goto cleanup;
    }
    frame = av_frame_alloc();
    packet = av_packet_alloc();
    output = fopen(job->outputPath, "wb+");
    if (frame == NULL || packet == NULL || output == NULL) {
        result = output == NULL ? AVERROR(errno != 0 ? errno : EIO) : AVERROR(ENOMEM);
        goto cleanup;
    }
    result = BetterTGFFmpegWriteWAVHeader(output, outputChannels, outputSampleRate, 0);
    if (result < 0 || fseek(output, 44, SEEK_SET) != 0) {
        result = result < 0 ? result : AVERROR(errno != 0 ? errno : EIO);
        goto cleanup;
    }

    while (!BetterTGFFmpegAudioDecodeJobIsCancelled(job) &&
           (result = av_read_frame(format, packet)) >= 0) {
        if (packet->stream_index == streamIndex) {
            result = avcodec_send_packet(decoder, packet);
            av_packet_unref(packet);
            if (result < 0) {
                goto cleanup;
            }
            result = BetterTGFFmpegDrainAudioDecoder(
                job,
                decoder,
                frame,
                resampler,
                output,
                outputChannels,
                outputSampleRate,
                &outputBytes
            );
            if (result < 0) {
                goto cleanup;
            }
        } else {
            av_packet_unref(packet);
        }
    }
    if (BetterTGFFmpegAudioDecodeJobIsCancelled(job)) {
        result = AVERROR_EXIT;
        goto cleanup;
    }
    if (result != AVERROR_EOF) {
        goto cleanup;
    }
    result = avcodec_send_packet(decoder, NULL);
    if (result < 0 && result != AVERROR_EOF) {
        goto cleanup;
    }
    result = BetterTGFFmpegDrainAudioDecoder(
        job,
        decoder,
        frame,
        resampler,
        output,
        outputChannels,
        outputSampleRate,
        &outputBytes
    );
    if (result < 0) {
        goto cleanup;
    }
    for (;;) {
        result = BetterTGFFmpegWriteResampledAudio(
            job,
            resampler,
            decoder,
            NULL,
            output,
            outputChannels,
            outputSampleRate,
            &outputBytes
        );
        if (result < 0) {
            goto cleanup;
        }
        if (result == 0) {
            break;
        }
    }
    result = BetterTGFFmpegWriteWAVHeader(output, outputChannels, outputSampleRate, outputBytes);
    if (result >= 0 && fflush(output) != 0) {
        result = AVERROR(errno != 0 ? errno : EIO);
    }

cleanup:
    if (output != NULL) {
        fclose(output);
    }
    av_packet_free(&packet);
    av_frame_free(&frame);
    swr_free(&resampler);
    avcodec_free_context(&decoder);
    avformat_close_input(&format);
    av_channel_layout_uninit(&outputLayout);
    if (result < 0) {
        remove(job->outputPath);
    }
    return result < 0 ? result : 0;
}

void BetterTGFFmpegAudioDecodeJobDestroy(BetterTGFFmpegAudioDecodeJob *job) {
    if (job == NULL) {
        return;
    }
    free(job->inputPath);
    free(job->outputPath);
    free(job);
}
