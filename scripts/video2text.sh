#!/usr/bin/env bash
# ============================================================
#  视频/音频 → 文字稿
#  用法: ai-video <视频或音频文件> [输出.txt]
#  路线: 优先硅基流动 SenseVoice API(快,¥极低);无 Key 则用本地
#        faster-whisper(需安装时带 --with-asr);两者都无则给指引。
#  输出: 与源文件同目录的 <名字>.转写.txt
# ============================================================
set -euo pipefail

KIT_DIR="/opt/agent-kit"
# shellcheck source=lib.sh
. "$KIT_DIR/scripts/lib.sh"

[ -f "$HOME/.config/agent-kit/env" ] && . "$HOME/.config/agent-kit/env"

IN="${1:-}"
[ -n "$IN" ] || die "用法:ai-video <视频或音频文件> [输出.txt]\n例如:ai-video 1-收件箱/对标视频.mp4"
# 允许直接粘 Windows 路径(C:\Users\...\视频.mp4,资源管理器里「复制文件地址」得到的,可能带引号)
IN="${IN#\"}"; IN="${IN%\"}"
case "$IN" in [A-Za-z]:\\*) IN="$(wslpath -u "$IN")" ;; esac
[ -f "$IN" ] || die "找不到文件:$IN"
OUT="${2:-${IN%.*}.转写.txt}"

command -v ffmpeg >/dev/null 2>&1 || die "缺少 ffmpeg(重跑 install.bat 可修复)"

TMPDIR_LOCAL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT
AUDIO="$TMPDIR_LOCAL/audio.mp3"

step "提取音轨…"
ffmpeg -y -loglevel error -i "$IN" -vn -ac 1 -ar 16000 -b:a 48k "$AUDIO" \
    || die "提取音轨失败:文件可能损坏,或者它没有声音"
DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$AUDIO" 2>/dev/null | cut -d. -f1)"
DUR="${DUR:-0}"
ok "音轨就绪(时长约 $((DUR / 60)) 分 $((DUR % 60)) 秒)"

# 在线转写:单次请求有体积/时长上限,超过 10 分钟就切段逐段转,再按顺序拼起来
sf_transcribe() { # <音频> <输出文本>
    local resp="$TMPDIR_LOCAL/resp.json" code
    code="$(curl -s -o "$resp" -w '%{http_code}' --connect-timeout 15 -m 600 \
        -X POST "https://api.siliconflow.cn/v1/audio/transcriptions" \
        -H "Authorization: Bearer $SILICONFLOW_API_KEY" \
        -F "model=FunAudioLLM/SenseVoiceSmall" \
        -F "file=@$1;type=audio/mpeg")" || code=000
    if [ "$code" = "200" ] && jq -e '.text' "$resp" >/dev/null 2>&1; then
        jq -r '.text' "$resp" > "$2"
        return 0
    fi
    case "$code" in
        401|403) warn "硅基流动拒绝了这个 Key(HTTP $code),运行 ai-config 重新填写" ;;
        000)     warn "连不上硅基流动(网络问题)" ;;
        *)       warn "在线转写失败(HTTP $code):$(head -c 200 "$resp" 2>/dev/null || true)" ;;
    esac
    return 1
}

if [ -n "${SILICONFLOW_API_KEY:-}" ]; then
    step "调用硅基流动 SenseVoice 转写…"
    SEG=600
    if [ "$DUR" -gt $((SEG + 60)) ]; then
        mkdir -p "$TMPDIR_LOCAL/parts"
        ffmpeg -y -loglevel error -i "$AUDIO" -f segment -segment_time "$SEG" -c copy \
            "$TMPDIR_LOCAL/parts/%03d.mp3"
        total="$(find "$TMPDIR_LOCAL/parts" -name '*.mp3' | wc -l)"
        note "视频较长,分成 $total 段转写…"
        : > "$TMPDIR_LOCAL/all.txt"
        i=0; fail=0
        for part in "$TMPDIR_LOCAL"/parts/*.mp3; do
            i=$((i + 1))
            printf '        第 %d/%d 段…\r' "$i" "$total"
            if sf_transcribe "$part" "$TMPDIR_LOCAL/part.txt" \
               || { sleep 3; sf_transcribe "$part" "$TMPDIR_LOCAL/part.txt"; }; then
                cat "$TMPDIR_LOCAL/part.txt" >> "$TMPDIR_LOCAL/all.txt"
                printf '\n' >> "$TMPDIR_LOCAL/all.txt"
            else
                fail=1; break
            fi
        done
        if [ "$fail" -eq 0 ]; then
            cp "$TMPDIR_LOCAL/all.txt" "$OUT"
            ok "转写完成 → $OUT"
            exit 0
        fi
    elif sf_transcribe "$AUDIO" "$OUT"; then
        ok "转写完成 → $OUT"
        exit 0
    fi
    warn "尝试本地转写…"
fi

ASR_PY="/opt/agent-kit-asr/bin/python"
if [ -x "$ASR_PY" ]; then
    step "本地 faster-whisper 转写(首次要下载模型,几分钟)…"
    "$ASR_PY" "$KIT_DIR/scripts/transcribe_local.py" "$AUDIO" > "$OUT"
    ok "转写完成 → $OUT"
    exit 0
fi

die "没有可用的转写方式。二选一:
  A. 推荐:去 siliconflow.cn 注册拿个 Key(送额度),然后运行 ai-config 填入
  B. 本地离线(不花钱但慢):sudo bash /opt/agent-kit/scripts/setup.sh --agents-only --agents opencode --with-asr"
