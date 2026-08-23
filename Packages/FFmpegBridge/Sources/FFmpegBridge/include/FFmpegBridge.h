#ifndef BETTERTG_FFMPEG_BRIDGE_H
#define BETTERTG_FFMPEG_BRIDGE_H

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/frame.h>
#include <libavutil/imgutils.h>
#include <libavutil/pixfmt.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>

const char *BetterTGFFmpegVersion(void);
int BetterTGFFmpegHasVP9Decoder(void);
int BetterTGFFmpegHasOpusDecoder(void);

#endif
