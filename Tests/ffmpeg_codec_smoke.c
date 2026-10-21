#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <stdio.h>

static int decode_file(const char *path) {
    AVFormatContext *format = NULL;
    AVCodecContext *codec = NULL;
    AVPacket *packet = NULL;
    AVFrame *frame = NULL;
    int stream_index = -1;
    int decoded_frames = 0;
    int result = 1;

    if (avformat_open_input(&format, path, NULL, NULL) < 0 ||
        avformat_find_stream_info(format, NULL) < 0) goto done;
    stream_index = av_find_best_stream(format, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    if (stream_index < 0) goto done;
    codec = avcodec_alloc_context3(NULL);
    if (!codec || avcodec_parameters_to_context(codec, format->streams[stream_index]->codecpar) < 0) goto done;
    const AVCodec *decoder = avcodec_find_decoder(codec->codec_id);
    if (!decoder || avcodec_open2(codec, decoder, NULL) < 0) goto done;
    packet = av_packet_alloc();
    frame = av_frame_alloc();
    if (!packet || !frame) goto done;

    while (av_read_frame(format, packet) >= 0) {
        if (packet->stream_index == stream_index && avcodec_send_packet(codec, packet) >= 0) {
            while (avcodec_receive_frame(codec, frame) >= 0) {
                decoded_frames++;
                av_frame_unref(frame);
            }
        }
        av_packet_unref(packet);
    }
    avcodec_send_packet(codec, NULL);
    while (avcodec_receive_frame(codec, frame) >= 0) {
        decoded_frames++;
        av_frame_unref(frame);
    }
    result = decoded_frames > 0 ? 0 : 1;
    if (!result) printf("%s: decoded %d frames (%s)\n", path, decoded_frames, decoder->name);

done:
    av_frame_free(&frame);
    av_packet_free(&packet);
    avcodec_free_context(&codec);
    avformat_close_input(&format);
    return result;
}

int main(int argc, char **argv) {
    int failed = 0;
    if (argc < 2) {
        fprintf(stderr, "usage: %s audio-file...\n", argv[0]);
        return 2;
    }
    av_log_set_level(AV_LOG_ERROR);
    for (int i = 1; i < argc; i++) failed |= decode_file(argv[i]);
    return failed ? 1 : 0;
}
