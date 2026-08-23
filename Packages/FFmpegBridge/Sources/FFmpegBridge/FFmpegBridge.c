#include "FFmpegBridge.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>

struct BetterTGFFmpegVideoDecoder {
    AVFormatContext *formatContext;
    AVCodecContext *codecContext;
    AVCodecContext *alphaCodecContext;
    AVFrame *frame;
    AVFrame *alphaFrame;
    AVPacket *packet;
    AVPacket *alphaPacket;
    struct SwsContext *scaleContext;
    struct SwsContext *alphaScaleContext;
    uint8_t *alphaBuffer;
    size_t alphaBufferSize;
    int videoStreamIndex;
    AVRational timeBase;
    double frameRate;
    double duration;
    int inputEnded;
    int draining;
    int alphaEnabled;
    int currentFrameHasAlpha;
};

const char *BetterTGFFmpegVersion(void) {
    return av_version_info();
}

int BetterTGFFmpegHasVP9Decoder(void) {
    return avcodec_find_decoder(AV_CODEC_ID_VP9) != NULL;
}

int BetterTGFFmpegHasOpusDecoder(void) {
    return avcodec_find_decoder(AV_CODEC_ID_OPUS) != NULL;
}

int BetterTGFFmpegHasGIFDecoder(void) {
    return avcodec_find_decoder(AV_CODEC_ID_GIF) != NULL;
}

static void BetterTGFFmpegVideoDecoderClose(BetterTGFFmpegVideoDecoder *decoder) {
    if (decoder == NULL) {
        return;
    }
    sws_freeContext(decoder->scaleContext);
    sws_freeContext(decoder->alphaScaleContext);
    free(decoder->alphaBuffer);
    av_packet_free(&decoder->alphaPacket);
    av_packet_free(&decoder->packet);
    av_frame_free(&decoder->alphaFrame);
    av_frame_free(&decoder->frame);
    avcodec_free_context(&decoder->alphaCodecContext);
    avcodec_free_context(&decoder->codecContext);
    avformat_close_input(&decoder->formatContext);
}

BetterTGFFmpegVideoDecoder *BetterTGFFmpegVideoDecoderCreate(const char *path) {
    if (path == NULL || path[0] == '\0') {
        return NULL;
    }

    BetterTGFFmpegVideoDecoder *decoder = calloc(1, sizeof(BetterTGFFmpegVideoDecoder));
    if (decoder == NULL) {
        return NULL;
    }

    if (avformat_open_input(&decoder->formatContext, path, NULL, NULL) < 0 ||
        avformat_find_stream_info(decoder->formatContext, NULL) < 0) {
        BetterTGFFmpegVideoDecoderClose(decoder);
        free(decoder);
        return NULL;
    }

    const AVCodec *codec = NULL;
    decoder->videoStreamIndex = av_find_best_stream(
        decoder->formatContext,
        AVMEDIA_TYPE_VIDEO,
        -1,
        -1,
        &codec,
        0
    );
    if (decoder->videoStreamIndex < 0 || codec == NULL) {
        BetterTGFFmpegVideoDecoderClose(decoder);
        free(decoder);
        return NULL;
    }

    AVStream *stream = decoder->formatContext->streams[decoder->videoStreamIndex];
    decoder->codecContext = avcodec_alloc_context3(codec);
    if (decoder->codecContext == NULL ||
        avcodec_parameters_to_context(decoder->codecContext, stream->codecpar) < 0 ||
        avcodec_open2(decoder->codecContext, codec, NULL) < 0) {
        BetterTGFFmpegVideoDecoderClose(decoder);
        free(decoder);
        return NULL;
    }

    decoder->frame = av_frame_alloc();
    decoder->packet = av_packet_alloc();
    if (stream->codecpar->codec_id == AV_CODEC_ID_VP9) {
        decoder->alphaCodecContext = avcodec_alloc_context3(codec);
        if (decoder->alphaCodecContext == NULL ||
            avcodec_parameters_to_context(decoder->alphaCodecContext, stream->codecpar) < 0 ||
            avcodec_open2(decoder->alphaCodecContext, codec, NULL) < 0) {
            BetterTGFFmpegVideoDecoderClose(decoder);
            free(decoder);
            return NULL;
        }
        decoder->alphaFrame = av_frame_alloc();
        decoder->alphaPacket = av_packet_alloc();
    }
    if (decoder->frame == NULL || decoder->packet == NULL ||
        (decoder->alphaCodecContext != NULL && (decoder->alphaFrame == NULL || decoder->alphaPacket == NULL))) {
        BetterTGFFmpegVideoDecoderClose(decoder);
        free(decoder);
        return NULL;
    }

    decoder->timeBase = stream->time_base;
    AVRational guessedFrameRate = av_guess_frame_rate(decoder->formatContext, stream, NULL);
    decoder->frameRate = guessedFrameRate.den != 0 ? av_q2d(guessedFrameRate) : 0.0;
    if (stream->duration != AV_NOPTS_VALUE) {
        decoder->duration = (double)stream->duration * av_q2d(stream->time_base);
    } else if (decoder->formatContext->duration != AV_NOPTS_VALUE) {
        decoder->duration = (double)decoder->formatContext->duration / AV_TIME_BASE;
    }
    return decoder;
}

void BetterTGFFmpegVideoDecoderDestroy(BetterTGFFmpegVideoDecoder *decoder) {
    if (decoder == NULL) {
        return;
    }
    BetterTGFFmpegVideoDecoderClose(decoder);
    free(decoder);
}

int BetterTGFFmpegVideoDecoderWidth(const BetterTGFFmpegVideoDecoder *decoder) {
    return decoder != NULL && decoder->codecContext != NULL ? decoder->codecContext->width : 0;
}

int BetterTGFFmpegVideoDecoderHeight(const BetterTGFFmpegVideoDecoder *decoder) {
    return decoder != NULL && decoder->codecContext != NULL ? decoder->codecContext->height : 0;
}

double BetterTGFFmpegVideoDecoderFrameRate(const BetterTGFFmpegVideoDecoder *decoder) {
    return decoder != NULL ? decoder->frameRate : 0.0;
}

double BetterTGFFmpegVideoDecoderDuration(const BetterTGFFmpegVideoDecoder *decoder) {
    return decoder != NULL ? decoder->duration : 0.0;
}

int BetterTGFFmpegVideoDecoderReset(BetterTGFFmpegVideoDecoder *decoder) {
    if (decoder == NULL || decoder->formatContext == NULL || decoder->codecContext == NULL) {
        return 0;
    }
    if (av_seek_frame(decoder->formatContext, decoder->videoStreamIndex, 0, AVSEEK_FLAG_BACKWARD) < 0) {
        return 0;
    }
    avcodec_flush_buffers(decoder->codecContext);
    if (decoder->alphaCodecContext != NULL) {
        avcodec_flush_buffers(decoder->alphaCodecContext);
        av_packet_unref(decoder->alphaPacket);
        av_frame_unref(decoder->alphaFrame);
    }
    av_packet_unref(decoder->packet);
    av_frame_unref(decoder->frame);
    decoder->inputEnded = 0;
    decoder->draining = 0;
    decoder->alphaEnabled = 0;
    decoder->currentFrameHasAlpha = 0;
    return 1;
}

static int BetterTGFFmpegVideoDecoderSendAlphaPacket(
    BetterTGFFmpegVideoDecoder *decoder,
    const AVPacket *packet
) {
    if (decoder->alphaCodecContext == NULL || decoder->alphaPacket == NULL) {
        return 0;
    }
    size_t sideDataSize = 0;
    uint8_t *sideData = av_packet_get_side_data(
        packet,
        AV_PKT_DATA_MATROSKA_BLOCKADDITIONAL,
        &sideDataSize
    );
    if (sideData == NULL || sideDataSize <= 8) {
        return 0;
    }
    uint64_t blockAdditionalId = 0;
    for (int index = 0; index < 8; index++) {
        blockAdditionalId = (blockAdditionalId << 8) | sideData[index];
    }
    if (blockAdditionalId != 1) {
        return 0;
    }

    av_packet_unref(decoder->alphaPacket);
    if (av_new_packet(decoder->alphaPacket, (int)(sideDataSize - 8)) < 0) {
        return -1;
    }
    memcpy(decoder->alphaPacket->data, sideData + 8, sideDataSize - 8);
    decoder->alphaPacket->pts = packet->pts;
    decoder->alphaPacket->dts = packet->dts;
    decoder->alphaPacket->duration = packet->duration;
    int result = avcodec_send_packet(decoder->alphaCodecContext, decoder->alphaPacket);
    av_packet_unref(decoder->alphaPacket);
    if (result < 0 && result != AVERROR(EAGAIN)) {
        return -1;
    }
    decoder->alphaEnabled = 1;
    return 1;
}

static int BetterTGFFmpegVideoDecoderReceive(BetterTGFFmpegVideoDecoder *decoder) {
    for (;;) {
        int result = avcodec_receive_frame(decoder->codecContext, decoder->frame);
        if (result == 0) {
            decoder->currentFrameHasAlpha = 0;
            if (decoder->alphaEnabled && decoder->alphaCodecContext != NULL) {
                av_frame_unref(decoder->alphaFrame);
                int alphaResult = avcodec_receive_frame(decoder->alphaCodecContext, decoder->alphaFrame);
                if (alphaResult == 0) {
                    decoder->currentFrameHasAlpha = 1;
                } else if (alphaResult != AVERROR(EAGAIN) && alphaResult != AVERROR_EOF) {
                    return -1;
                }
            }
            return 1;
        }
        if (result == AVERROR_EOF) {
            return 0;
        }
        if (result != AVERROR(EAGAIN)) {
            return -1;
        }

        if (decoder->inputEnded) {
            if (!decoder->draining) {
                result = avcodec_send_packet(decoder->codecContext, NULL);
                if (decoder->alphaEnabled && decoder->alphaCodecContext != NULL) {
                    int alphaResult = avcodec_send_packet(decoder->alphaCodecContext, NULL);
                    if (alphaResult < 0 && alphaResult != AVERROR_EOF) {
                        return -1;
                    }
                }
                decoder->draining = 1;
                if (result < 0 && result != AVERROR_EOF) {
                    return -1;
                }
                continue;
            }
            return 0;
        }

        for (;;) {
            result = av_read_frame(decoder->formatContext, decoder->packet);
            if (result < 0) {
                decoder->inputEnded = 1;
                break;
            }
            if (decoder->packet->stream_index == decoder->videoStreamIndex) {
                int alphaResult = BetterTGFFmpegVideoDecoderSendAlphaPacket(decoder, decoder->packet);
                if (alphaResult < 0) {
                    av_packet_unref(decoder->packet);
                    return -1;
                }
                result = avcodec_send_packet(decoder->codecContext, decoder->packet);
                av_packet_unref(decoder->packet);
                if (result < 0 && result != AVERROR(EAGAIN)) {
                    return -1;
                }
                break;
            }
            av_packet_unref(decoder->packet);
        }
    }
}

int BetterTGFFmpegVideoDecoderReadFrame(
    BetterTGFFmpegVideoDecoder *decoder,
    uint8_t *destination,
    int destinationWidth,
    int destinationHeight,
    int destinationBytesPerRow,
    double *presentationTime,
    double *frameDuration,
    int *hasAlpha
) {
    if (decoder == NULL || destination == NULL || destinationWidth <= 0 || destinationHeight <= 0 ||
        destinationBytesPerRow < destinationWidth * 4) {
        return -1;
    }

    av_frame_unref(decoder->frame);
    int result = BetterTGFFmpegVideoDecoderReceive(decoder);
    if (result <= 0) {
        return result;
    }

    enum AVPixelFormat sourceFormat = (enum AVPixelFormat)decoder->frame->format;
    decoder->scaleContext = sws_getCachedContext(
        decoder->scaleContext,
        decoder->frame->width,
        decoder->frame->height,
        sourceFormat,
        destinationWidth,
        destinationHeight,
        AV_PIX_FMT_BGRA,
        SWS_BILINEAR,
        NULL,
        NULL,
        NULL
    );
    if (decoder->scaleContext == NULL) {
        return -1;
    }

    uint8_t *destinationPlanes[4] = { destination, NULL, NULL, NULL };
    int destinationLineSizes[4] = { destinationBytesPerRow, 0, 0, 0 };
    if (sws_scale(
            decoder->scaleContext,
            (const uint8_t *const *)decoder->frame->data,
            decoder->frame->linesize,
            0,
            decoder->frame->height,
            destinationPlanes,
            destinationLineSizes
        ) <= 0) {
        return -1;
    }

    const AVPixFmtDescriptor *descriptor = av_pix_fmt_desc_get(sourceFormat);
    int frameHasAlpha = descriptor != NULL && (descriptor->flags & AV_PIX_FMT_FLAG_ALPHA) != 0;
    if (decoder->currentFrameHasAlpha) {
        size_t requiredAlphaBufferSize = (size_t)destinationWidth * (size_t)destinationHeight;
        if (decoder->alphaBufferSize < requiredAlphaBufferSize) {
            uint8_t *updatedBuffer = realloc(decoder->alphaBuffer, requiredAlphaBufferSize);
            if (updatedBuffer == NULL) {
                return -1;
            }
            decoder->alphaBuffer = updatedBuffer;
            decoder->alphaBufferSize = requiredAlphaBufferSize;
        }
        enum AVPixelFormat alphaFormat = (enum AVPixelFormat)decoder->alphaFrame->format;
        decoder->alphaScaleContext = sws_getCachedContext(
            decoder->alphaScaleContext,
            decoder->alphaFrame->width,
            decoder->alphaFrame->height,
            alphaFormat,
            destinationWidth,
            destinationHeight,
            AV_PIX_FMT_GRAY8,
            SWS_BILINEAR,
            NULL,
            NULL,
            NULL
        );
        if (decoder->alphaScaleContext == NULL) {
            return -1;
        }
        uint8_t *alphaPlanes[4] = { decoder->alphaBuffer, NULL, NULL, NULL };
        int alphaLineSizes[4] = { destinationWidth, 0, 0, 0 };
        if (sws_scale(
                decoder->alphaScaleContext,
                (const uint8_t *const *)decoder->alphaFrame->data,
                decoder->alphaFrame->linesize,
                0,
                decoder->alphaFrame->height,
                alphaPlanes,
                alphaLineSizes
            ) <= 0) {
            return -1;
        }
        frameHasAlpha = 1;
        for (int y = 0; y < destinationHeight; y++) {
            uint8_t *row = destination + y * destinationBytesPerRow;
            uint8_t *alphaRow = decoder->alphaBuffer + y * destinationWidth;
            for (int x = 0; x < destinationWidth; x++) {
                uint8_t *pixel = row + x * 4;
                int alpha = alphaRow[x];
                pixel[0] = (uint8_t)((pixel[0] * alpha + 127) / 255);
                pixel[1] = (uint8_t)((pixel[1] * alpha + 127) / 255);
                pixel[2] = (uint8_t)((pixel[2] * alpha + 127) / 255);
                pixel[3] = (uint8_t)alpha;
            }
        }
    } else if (frameHasAlpha) {
        for (int y = 0; y < destinationHeight; y++) {
            uint8_t *row = destination + y * destinationBytesPerRow;
            for (int x = 0; x < destinationWidth; x++) {
                uint8_t *pixel = row + x * 4;
                int alpha = pixel[3];
                pixel[0] = (uint8_t)((pixel[0] * alpha + 127) / 255);
                pixel[1] = (uint8_t)((pixel[1] * alpha + 127) / 255);
                pixel[2] = (uint8_t)((pixel[2] * alpha + 127) / 255);
            }
        }
    }

    int64_t timestamp = decoder->frame->best_effort_timestamp;
    if (presentationTime != NULL) {
        *presentationTime = timestamp != AV_NOPTS_VALUE ? (double)timestamp * av_q2d(decoder->timeBase) : 0.0;
    }
    if (frameDuration != NULL) {
        double duration = decoder->frame->duration > 0
            ? (double)decoder->frame->duration * av_q2d(decoder->timeBase)
            : (decoder->frameRate > 0.0 ? 1.0 / decoder->frameRate : 1.0 / 30.0);
        *frameDuration = duration;
    }
    if (hasAlpha != NULL) {
        *hasAlpha = frameHasAlpha;
    }
    return 1;
}
