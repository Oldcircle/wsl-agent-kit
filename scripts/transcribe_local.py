#!/usr/bin/env python3
"""本地语音转写(faster-whisper),由 video2text.sh 调用。

用法: python transcribe_local.py <音频文件> [语言代码,默认自动检测]
输出: 纯文本到 stdout(进度信息走 stderr)
"""
import os
import sys

os.environ.setdefault("HF_ENDPOINT", "https://hf-mirror.com")  # 国内镜像


def main() -> int:
    if len(sys.argv) < 2:
        print("用法: transcribe_local.py <音频文件> [语言]", file=sys.stderr)
        return 2
    audio = sys.argv[1]
    language = sys.argv[2] if len(sys.argv) > 2 else None

    from faster_whisper import WhisperModel  # 延迟导入,报错信息更友好

    print("加载模型 small(首次运行会自动下载)…", file=sys.stderr)
    model = WhisperModel("small", device="cpu", compute_type="int8")
    segments, info = model.transcribe(
        audio, language=language, vad_filter=True, beam_size=5
    )
    print(f"检测语言: {info.language} (置信度 {info.language_probability:.2f})",
          file=sys.stderr)
    for seg in segments:
        print(seg.text.strip())
    return 0


if __name__ == "__main__":
    sys.exit(main())
