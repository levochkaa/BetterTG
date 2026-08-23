#include "FFmpegBridge.h"

#include <libavutil/audio_fifo.h>
#include <libavutil/channel_layout.h>
#include <libavutil/mathematics.h>
#include <libavutil/samplefmt.h>

#include <string.h>

static int BetterTGFFmpegWriteEncodedPackets(
    AVCodecContext *encoder,
    AVFormatContext *output,
    AVStream *stream,
    AVPacket *packet
) {
    for (;;) {
        int result = avcodec_receive_packet(encoder, packet);
        if (result == AVERROR(EAGAIN) || result == AVERROR_EOF) {
            return 0;
        }
        if (result < 0) {
            return result;
        }
        av_packet_rescale_ts(packet, encoder->time_base, stream->time_base);
        packet->stream_index = stream->index;
        result = av_interleaved_write_frame(output, packet);
        av_packet_unref(packet);
        if (result < 0) {
            return result;
        }
    }
}

static int BetterTGFFmpegEncodeAvailableSamples(
    AVAudioFifo *fifo,
    AVCodecContext *encoder,
    AVFormatContext *output,
    AVStream *stream,
    AVPacket *packet,
    int flushPartial,
    int64_t *nextPresentationTime
) {
    const int frameSize = encoder->frame_size > 0 ? encoder->frame_size : 960;
    while (av_audio_fifo_size(fifo) >= frameSize ||
           (flushPartial && av_audio_fifo_size(fifo) > 0)) {
        const int available = av_audio_fifo_size(fifo);
        const int samplesToRead = available < frameSize ? available : frameSize;
        AVFrame *frame = av_frame_alloc();
        if (frame == NULL) {
            return AVERROR(ENOMEM);
        }
        frame->format = encoder->sample_fmt;
        frame->sample_rate = encoder->sample_rate;
        frame->nb_samples = frameSize;
        int result = av_channel_layout_copy(&frame->ch_layout, &encoder->ch_layout);
        if (result >= 0) {
            result = av_frame_get_buffer(frame, 0);
        }
        if (result >= 0) {
            result = av_audio_fifo_read(fifo, (void *const *)frame->extended_data, samplesToRead);
            if (result != samplesToRead) {
                result = result < 0 ? result : AVERROR(EIO);
            }
        }
        if (result >= 0 && samplesToRead < frameSize) {
            result = av_samples_set_silence(
                frame->extended_data,
                samplesToRead,
                frameSize - samplesToRead,
                encoder->ch_layout.nb_channels,
                encoder->sample_fmt
            );
        }
        if (result >= 0) {
            frame->pts = *nextPresentationTime;
            *nextPresentationTime += frameSize;
            result = avcodec_send_frame(encoder, frame);
        }
        av_frame_free(&frame);
        if (result < 0) {
            return result;
        }
        result = BetterTGFFmpegWriteEncodedPackets(encoder, output, stream, packet);
        if (result < 0) {
            return result;
        }
    }
    return 0;
}

static int BetterTGFFmpegAppendConvertedFrame(
    const AVFrame *frame,
    SwrContext *resampler,
    AVAudioFifo *fifo,
    const AVCodecContext *decoder,
    const AVCodecContext *encoder
) {
    const int64_t delay = swr_get_delay(resampler, decoder->sample_rate);
    const int outputCapacity = (int)av_rescale_rnd(
        delay + frame->nb_samples,
        encoder->sample_rate,
        decoder->sample_rate,
        AV_ROUND_UP
    );
    uint8_t **convertedData = NULL;
    int lineSize = 0;
    int result = av_samples_alloc_array_and_samples(
        &convertedData,
        &lineSize,
        encoder->ch_layout.nb_channels,
        outputCapacity,
        encoder->sample_fmt,
        0
    );
    if (result < 0) {
        return result;
    }
    const int convertedSamples = swr_convert(
        resampler,
        convertedData,
        outputCapacity,
        (const uint8_t **)frame->extended_data,
        frame->nb_samples
    );
    if (convertedSamples < 0) {
        result = convertedSamples;
    } else {
        result = av_audio_fifo_write(fifo, (void *const *)convertedData, convertedSamples);
        if (result == convertedSamples) {
            result = 0;
        } else if (result >= 0) {
            result = AVERROR(EIO);
        }
    }
    av_freep(&convertedData[0]);
    av_freep(&convertedData);
    return result;
}

static int BetterTGFFmpegFlushResampler(
    SwrContext *resampler,
    AVAudioFifo *fifo,
    const AVCodecContext *encoder
) {
    for (;;) {
        const int outputCapacity = swr_get_out_samples(resampler, 0);
        if (outputCapacity <= 0) {
            return outputCapacity;
        }
        uint8_t **convertedData = NULL;
        int lineSize = 0;
        int result = av_samples_alloc_array_and_samples(
            &convertedData,
            &lineSize,
            encoder->ch_layout.nb_channels,
            outputCapacity,
            encoder->sample_fmt,
            0
        );
        if (result < 0) {
            return result;
        }
        const int convertedSamples = swr_convert(
            resampler,
            convertedData,
            outputCapacity,
            NULL,
            0
        );
        if (convertedSamples < 0) {
            result = convertedSamples;
        } else if (convertedSamples == 0) {
            result = 0;
        } else {
            result = av_audio_fifo_write(fifo, (void *const *)convertedData, convertedSamples);
            if (result == convertedSamples) {
                result = 0;
            } else if (result >= 0) {
                result = AVERROR(EIO);
            }
        }
        av_freep(&convertedData[0]);
        av_freep(&convertedData);
        if (result < 0 || convertedSamples == 0) {
            return result;
        }
    }
}

static int BetterTGFFmpegDrainDecoder(
    AVCodecContext *decoder,
    AVFrame *decodedFrame,
    SwrContext *resampler,
    AVAudioFifo *fifo,
    AVCodecContext *encoder,
    AVFormatContext *output,
    AVStream *stream,
    AVPacket *outputPacket,
    int64_t *nextPresentationTime
) {
    for (;;) {
        int result = avcodec_receive_frame(decoder, decodedFrame);
        if (result == AVERROR(EAGAIN) || result == AVERROR_EOF) {
            return 0;
        }
        if (result < 0) {
            return result;
        }
        result = BetterTGFFmpegAppendConvertedFrame(
            decodedFrame,
            resampler,
            fifo,
            decoder,
            encoder
        );
        av_frame_unref(decodedFrame);
        if (result < 0) {
            return result;
        }
        result = BetterTGFFmpegEncodeAvailableSamples(
            fifo,
            encoder,
            output,
            stream,
            outputPacket,
            0,
            nextPresentationTime
        );
        if (result < 0) {
            return result;
        }
    }
}

static enum AVSampleFormat BetterTGFFmpegSelectSampleFormat(const AVCodec *codec) {
    const void *configurations = NULL;
    int count = 0;
    if (avcodec_get_supported_config(
            NULL,
            codec,
            AV_CODEC_CONFIG_SAMPLE_FORMAT,
            0,
            &configurations,
            &count
        ) < 0 || configurations == NULL || count == 0) {
        return AV_SAMPLE_FMT_FLTP;
    }
    const enum AVSampleFormat *formats = configurations;
    for (int index = 0; index < count; index++) {
        if (formats[index] == AV_SAMPLE_FMT_FLTP) {
            return formats[index];
        }
    }
    return formats[0];
}

int BetterTGFFmpegTranscodeVoiceNote(
    const char *inputPath,
    const char *outputPath,
    int bitrate
) {
    if (inputPath == NULL || inputPath[0] == '\0' ||
        outputPath == NULL || outputPath[0] == '\0') {
        return AVERROR(EINVAL);
    }

    AVFormatContext *input = NULL;
    AVFormatContext *output = NULL;
    AVCodecContext *decoder = NULL;
    AVCodecContext *encoder = NULL;
    SwrContext *resampler = NULL;
    AVAudioFifo *fifo = NULL;
    AVFrame *decodedFrame = NULL;
    AVPacket *inputPacket = NULL;
    AVPacket *outputPacket = NULL;
    AVStream *outputStream = NULL;
    int inputStreamIndex = -1;
    int outputOpened = 0;
    int headerWritten = 0;
    int result = AVERROR_UNKNOWN;
    int64_t nextPresentationTime = 0;

    result = avformat_open_input(&input, inputPath, NULL, NULL);
    if (result < 0) {
        goto cleanup;
    }
    result = avformat_find_stream_info(input, NULL);
    if (result < 0) {
        goto cleanup;
    }
    const AVCodec *decoderCodec = NULL;
    inputStreamIndex = av_find_best_stream(
        input,
        AVMEDIA_TYPE_AUDIO,
        -1,
        -1,
        &decoderCodec,
        0
    );
    if (inputStreamIndex < 0 || decoderCodec == NULL) {
        result = inputStreamIndex < 0 ? inputStreamIndex : AVERROR_DECODER_NOT_FOUND;
        goto cleanup;
    }
    decoder = avcodec_alloc_context3(decoderCodec);
    if (decoder == NULL) {
        result = AVERROR(ENOMEM);
        goto cleanup;
    }
    result = avcodec_parameters_to_context(decoder, input->streams[inputStreamIndex]->codecpar);
    if (result < 0) {
        goto cleanup;
    }
    result = avcodec_open2(decoder, decoderCodec, NULL);
    if (result < 0) {
        goto cleanup;
    }

    const AVCodec *encoderCodec = avcodec_find_encoder(AV_CODEC_ID_OPUS);
    if (encoderCodec == NULL) {
        result = AVERROR_ENCODER_NOT_FOUND;
        goto cleanup;
    }
    result = avformat_alloc_output_context2(&output, NULL, "ogg", outputPath);
    if (result < 0 || output == NULL) {
        result = result < 0 ? result : AVERROR_MUXER_NOT_FOUND;
        goto cleanup;
    }
    outputStream = avformat_new_stream(output, NULL);
    encoder = avcodec_alloc_context3(encoderCodec);
    if (outputStream == NULL || encoder == NULL) {
        result = AVERROR(ENOMEM);
        goto cleanup;
    }
    encoder->bit_rate = bitrate > 0 ? bitrate : 32000;
    encoder->sample_rate = 48000;
    encoder->sample_fmt = BetterTGFFmpegSelectSampleFormat(encoderCodec);
    encoder->time_base = (AVRational){1, encoder->sample_rate};
    encoder->strict_std_compliance = FF_COMPLIANCE_EXPERIMENTAL;
    av_channel_layout_default(&encoder->ch_layout, 1);
    if ((output->oformat->flags & AVFMT_GLOBALHEADER) != 0) {
        encoder->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    }
    result = avcodec_open2(encoder, encoderCodec, NULL);
    if (result < 0) {
        goto cleanup;
    }
    outputStream->time_base = encoder->time_base;
    result = avcodec_parameters_from_context(outputStream->codecpar, encoder);
    if (result < 0) {
        goto cleanup;
    }

    result = swr_alloc_set_opts2(
        &resampler,
        &encoder->ch_layout,
        encoder->sample_fmt,
        encoder->sample_rate,
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
    fifo = av_audio_fifo_alloc(
        encoder->sample_fmt,
        encoder->ch_layout.nb_channels,
        encoder->frame_size > 0 ? encoder->frame_size : 960
    );
    decodedFrame = av_frame_alloc();
    inputPacket = av_packet_alloc();
    outputPacket = av_packet_alloc();
    if (fifo == NULL || decodedFrame == NULL || inputPacket == NULL || outputPacket == NULL) {
        result = AVERROR(ENOMEM);
        goto cleanup;
    }
    if ((output->oformat->flags & AVFMT_NOFILE) == 0) {
        result = avio_open(&output->pb, outputPath, AVIO_FLAG_WRITE);
        if (result < 0) {
            goto cleanup;
        }
        outputOpened = 1;
    }
    result = avformat_write_header(output, NULL);
    if (result < 0) {
        goto cleanup;
    }
    headerWritten = 1;

    while ((result = av_read_frame(input, inputPacket)) >= 0) {
        if (inputPacket->stream_index == inputStreamIndex) {
            result = avcodec_send_packet(decoder, inputPacket);
            av_packet_unref(inputPacket);
            if (result < 0) {
                goto cleanup;
            }
            result = BetterTGFFmpegDrainDecoder(
                decoder,
                decodedFrame,
                resampler,
                fifo,
                encoder,
                output,
                outputStream,
                outputPacket,
                &nextPresentationTime
            );
            if (result < 0) {
                goto cleanup;
            }
        } else {
            av_packet_unref(inputPacket);
        }
    }
    if (result != AVERROR_EOF) {
        goto cleanup;
    }
    result = avcodec_send_packet(decoder, NULL);
    if (result < 0 && result != AVERROR_EOF) {
        goto cleanup;
    }
    result = BetterTGFFmpegDrainDecoder(
        decoder,
        decodedFrame,
        resampler,
        fifo,
        encoder,
        output,
        outputStream,
        outputPacket,
        &nextPresentationTime
    );
    if (result < 0) {
        goto cleanup;
    }

    result = BetterTGFFmpegFlushResampler(resampler, fifo, encoder);
    if (result < 0) {
        goto cleanup;
    }
    result = BetterTGFFmpegEncodeAvailableSamples(
        fifo,
        encoder,
        output,
        outputStream,
        outputPacket,
        1,
        &nextPresentationTime
    );
    if (result < 0) {
        goto cleanup;
    }
    result = avcodec_send_frame(encoder, NULL);
    if (result < 0 && result != AVERROR_EOF) {
        goto cleanup;
    }
    result = BetterTGFFmpegWriteEncodedPackets(encoder, output, outputStream, outputPacket);
    if (result < 0) {
        goto cleanup;
    }
    result = av_write_trailer(output);
    if (result >= 0) {
        headerWritten = 0;
    }

cleanup:
    av_packet_free(&outputPacket);
    av_packet_free(&inputPacket);
    av_frame_free(&decodedFrame);
    av_audio_fifo_free(fifo);
    swr_free(&resampler);
    avcodec_free_context(&encoder);
    avcodec_free_context(&decoder);
    if (headerWritten && output != NULL) {
        av_write_trailer(output);
    }
    if (outputOpened && output != NULL && output->pb != NULL) {
        avio_closep(&output->pb);
    }
    avformat_free_context(output);
    avformat_close_input(&input);
    return result < 0 ? result : 0;
}

int BetterTGFFmpegIsOggOpusFile(const char *path) {
    if (path == NULL || path[0] == '\0') {
        return 0;
    }
    AVFormatContext *format = NULL;
    if (avformat_open_input(&format, path, NULL, NULL) < 0 ||
        avformat_find_stream_info(format, NULL) < 0) {
        avformat_close_input(&format);
        return 0;
    }
    const int streamIndex = av_find_best_stream(
        format,
        AVMEDIA_TYPE_AUDIO,
        -1,
        -1,
        NULL,
        0
    );
    const int isOgg = format->iformat != NULL &&
        format->iformat->name != NULL &&
        strstr(format->iformat->name, "ogg") != NULL;
    if (!isOgg || streamIndex < 0) {
        avformat_close_input(&format);
        return 0;
    }
    AVStream *stream = format->streams[streamIndex];
    const int isOpus = stream->codecpar->codec_id == AV_CODEC_ID_OPUS;
    const int isMono = stream->codecpar->ch_layout.nb_channels == 1;
    const int is48KHz = stream->codecpar->sample_rate == 48000;
    const int hasDuration = stream->duration > 0 || format->duration > 0;
    const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
    AVCodecContext *decoder = codec != NULL ? avcodec_alloc_context3(codec) : NULL;
    AVFrame *frame = av_frame_alloc();
    AVPacket *packet = av_packet_alloc();
    int decodedFrame = 0;
    if (decoder != NULL && frame != NULL && packet != NULL &&
        avcodec_parameters_to_context(decoder, stream->codecpar) >= 0 &&
        avcodec_open2(decoder, codec, NULL) >= 0) {
        while (!decodedFrame && av_read_frame(format, packet) >= 0) {
            if (packet->stream_index == streamIndex &&
                avcodec_send_packet(decoder, packet) >= 0) {
                decodedFrame = avcodec_receive_frame(decoder, frame) == 0 && frame->nb_samples > 0;
            }
            av_packet_unref(packet);
        }
    }
    av_packet_free(&packet);
    av_frame_free(&frame);
    avcodec_free_context(&decoder);
    avformat_close_input(&format);
    return isOpus && isMono && is48KHz && hasDuration && decodedFrame ? 1 : 0;
}
