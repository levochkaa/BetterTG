#include "FFmpegBridge.h"

const char *BetterTGFFmpegVersion(void) {
    return av_version_info();
}

int BetterTGFFmpegHasVP9Decoder(void) {
    return avcodec_find_decoder(AV_CODEC_ID_VP9) != NULL;
}

int BetterTGFFmpegHasOpusDecoder(void) {
    return avcodec_find_decoder(AV_CODEC_ID_OPUS) != NULL;
}
