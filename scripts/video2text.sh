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
[ -n "$IN" ] || die "用法:ai-video <视频或音频文件> [输出.txt]\n例如:ai-video inbox/对标视频.mp4"
[ -f "$IN" ] || die "找不到文件:$IN"
OUT="${2:-${IN%.*}.转写.txt}"

command -v ffmpeg >/dev/null 2>&1 || die "缺少 ffmpeg(重跑 install.bat 可修复)"

TMPDIR_LOCAL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT
AUDIO="$TMPDIR_LOCAL/audio.mp3"

step "提取音轨…"
ffmpeg -y -loglevel error -i "$IN" -vn -ac 1 -ar 16000 -b:a 48k "$AUDIO"
size_mb=$(( $(stat -c %s "$AUDIO") / 1024 / 1024 ))
ok "音轨就绪(${size_mb}MB)"
if [ "$size_mb" -ge 48 ]; then
    warn "音频超过 48MB(约1小时以上),在线接口可能拒收;过长视频建议先剪段再转。"
fi

if [ -n "${SILICONFLOW_API_KEY:-}" ]; then
    step "调用硅基流动 SenseVoice 转写…"
    RESP="$TMPDIR_LOCAL/resp.json"
    HTTP_CODE="$(curl -s -o "$RESP" -w '%{http_code}' -m 600 \
        -X POST "https://api.siliconflow.cn/v1/audio/transcriptions" \
        -H "Authorization: Bearer $SILICONFLOW_API_KEY" \
        -F "model=FunAudioLLM/SenseVoiceSmall" \
        -F "file=@$AUDIO;type=audio/mpeg")" || HTTP_CODE=000
    if [ "$HTTP_CODE" = "200" ] && jq -e '.text' "$RESP" >/dev/null 2>&1; then
        jq -r '.text' "$RESP" > "$OUT"
        ok "转写完成 → $OUT"
        exit 0
    fi
    warn "在线转写失败(HTTP $HTTP_CODE):$(head -c 200 "$RESP" 2>/dev/null || true)"
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
  B. 本地离线:让安装人重跑一次安装并带 --with-asr 参数(见 docs/USAGE.md)"
