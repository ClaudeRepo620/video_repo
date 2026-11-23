#!/usr/bin/env bash
# Final audio pass for every upload (free, ffmpeg only).
#   finish_audio.sh <in.mp4> <out.mp4> [music.mp3|none] [music_LUFS: -25 Rota/Kokpit, -28 Ayet]
# 1) optional background music from the pool: looped/trimmed to the video, faded in/out,
#    normalised to a fixed loudness, ducked under the voice (sidechain) and hard-limited:
#    measured 18-26 dB below the voice while it speaks and always >= 7 dB below the average voice level
# 2) whole mix tuned from A=440 Hz to A=432 Hz (pitch -31.8 cents, same speed and length)
# 3) loudness normalised for Shorts/Reels (-14 LUFS, true peak -1 dB)
set -euo pipefail
IN="$1"; OUT="$2"; MUSIC="${3:-none}"; LVL="${4:--25}"
SR=48000
D=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$IN")
TUNE="asetrate=${SR}*432/440,aresample=${SR},atempo=440/432"
if [ "$MUSIC" != "none" ] && [ -f "$MUSIC" ]; then
  FO=$(python3 -c "print(max(0, $D-2.5))")
  ffmpeg -v error -y -i "$IN" -stream_loop -1 -i "$MUSIC" -filter_complex \
   "[0:a]aresample=${SR},asplit=2[v][key]; \
    [1:a]aresample=${SR},atrim=0:${D},asetpts=PTS-STARTPTS,loudnorm=I=${LVL}:TP=-9:LRA=6,aresample=${SR},afade=t=in:d=1.2,afade=t=out:st=${FO}:d=2.5[m]; \
    [m][key]sidechaincompress=threshold=0.05:ratio=2.5:attack=20:release=400:makeup=1,alimiter=limit=0.1:level=disabled[duck]; \
    [v][duck]amix=inputs=2:weights=1 1:normalize=0:duration=first,${TUNE},loudnorm=I=-14:TP=-1:LRA=11[a]" \
   -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 192k -movflags +faststart "$OUT"
else
  ffmpeg -v error -y -i "$IN" -filter_complex "[0:a]aresample=${SR},${TUNE},loudnorm=I=-14:TP=-1:LRA=11[a]" \
   -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 192k -movflags +faststart "$OUT"
fi
echo "$OUT"
