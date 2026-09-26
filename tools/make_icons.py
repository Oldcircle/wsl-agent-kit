#!/usr/bin/env python3
"""生成 assets/icons/*.ico(桌面/开始菜单/控制台窗口用的图标)。

用法: uv run --with pillow tools/make_icons.py
产物已提交进仓库,改图标时才需要重跑。每个 .ico 含 16~256 共 7 个尺寸,
在 1024 画布上画、再逐尺寸缩小,保证小图标边缘干净。
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "icons"
S = 1024  # 工作画布
SIZES = [256, 128, 64, 48, 32, 24, 16]
WHITE = (255, 255, 255, 255)


def hex_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def tile(top: str, bottom: str) -> Image.Image:
    """圆角方块 + 竖向渐变 + 轻微阴影。"""
    a, b = hex_rgb(top), hex_rgb(bottom)
    grad = Image.new("RGBA", (S, S))
    px = grad.load()
    for y in range(S):
        t = y / (S - 1)
        c = tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3)) + (255,)
        for x in range(S):
            px[x, y] = c
    mask = Image.new("L", (S, S), 0)
    m = 64
    ImageDraw.Draw(mask).rounded_rectangle((m, m, S - m, S - m), radius=210, fill=255)
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((m, m + 18, S - m, S - m + 18), radius=210,
                                             fill=(0, 0, 0, 70))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    img.alpha_composite(shadow)
    img.paste(grad, (0, 0), mask)
    return img


def sparkle(d: ImageDraw.ImageDraw, cx: float, cy: float, r: float, fill) -> None:
    """四角星:AI 的通用记号。"""
    k = r * 0.28
    d.polygon([(cx, cy - r), (cx + k, cy - k), (cx + r, cy), (cx + k, cy + k),
               (cx, cy + r), (cx - k, cy + k), (cx - r, cy), (cx - k, cy - k)], fill=fill)


def icon_assistant() -> Image.Image:
    img = tile("#6366F1", "#8B5CF6")
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((210, 250, 814, 690), radius=130, fill=WHITE)
    d.polygon([(330, 660), (300, 820), (470, 680)], fill=WHITE)  # 气泡尾巴
    sparkle(d, 512, 470, 150, hex_rgb("#7C3AED") + (255,))
    sparkle(d, 668, 360, 55, hex_rgb("#A78BFA") + (255,))
    return img


def icon_workspace() -> Image.Image:
    img = tile("#F59E0B", "#EA580C")
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((200, 300, 520, 420), radius=40, fill=(255, 237, 213, 255))  # 标签页
    d.rounded_rectangle((200, 360, 824, 780), radius=60, fill=WHITE)
    sparkle(d, 512, 570, 120, hex_rgb("#EA580C") + (255,))
    return img


def icon_console() -> Image.Image:
    img = tile("#14B8A6", "#0EA5E9")
    d = ImageDraw.Draw(img)
    for y, kx in ((340, 400), (512, 640), (684, 470)):
        d.rounded_rectangle((230, y - 26, 794, y + 26), radius=26, fill=(255, 255, 255, 150))
        d.ellipse((kx - 70, y - 70, kx + 70, y + 70), fill=WHITE)
    return img


def icon_config() -> Image.Image:
    img = tile("#0EA5E9", "#2563EB")
    d = ImageDraw.Draw(img)
    d.ellipse((220, 300, 520, 600), fill=WHITE)
    d.ellipse((315, 395, 425, 505), fill=hex_rgb("#1D6FE0") + (255,))  # 钥匙孔
    d.rounded_rectangle((480, 415, 820, 485), radius=30, fill=WHITE)  # 钥匙杆
    d.rectangle((660, 470, 715, 590), fill=WHITE)
    d.rectangle((750, 470, 805, 560), fill=WHITE)
    return img


def icon_guide() -> Image.Image:
    img = tile("#22C55E", "#059669")
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((280, 210, 744, 814), radius=50, fill=WHITE)
    for i, w in enumerate((380, 380, 300, 380, 240)):
        y = 330 + i * 92
        d.rounded_rectangle((350, y, 350 + w, y + 36), radius=18,
                            fill=hex_rgb("#10B981") + (255,))
    return img


def icon_repair() -> Image.Image:
    img = tile("#64748B", "#334155")
    d = ImageDraw.Draw(img)
    # 环形箭头(重新安装/修复)
    box = (240, 240, 784, 784)
    d.arc(box, start=-60, end=250, fill=WHITE, width=96)
    d.polygon([(640, 150), (820, 330), (600, 380)], fill=WHITE)
    return img


def icon_uninstall() -> Image.Image:
    img = tile("#F87171", "#DC2626")
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((250, 280, 774, 350), radius=30, fill=WHITE)  # 盖子
    d.rounded_rectangle((430, 220, 594, 300), radius=30, fill=WHITE)  # 把手
    d.rounded_rectangle((310, 380, 714, 800), radius=50, fill=WHITE)  # 桶身
    for x in (400, 497, 594):
        d.rounded_rectangle((x - 5, 450, x + 35, 730), radius=20,
                            fill=hex_rgb("#E14B4B") + (255,))
    return img


def save_ico(img: Image.Image, name: str) -> None:
    frames = [img.resize((s, s), Image.Resampling.LANCZOS) for s in SIZES]
    path = OUT / f"{name}.ico"
    frames[0].save(path, format="ICO", sizes=[(s, s) for s in SIZES], append_images=frames[1:])
    frames[0].save(OUT / f"{name}.png")  # 预览/文档用
    print(f"wrote {path.relative_to(ROOT)}")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in (("assistant", icon_assistant), ("workspace", icon_workspace),
                     ("console", icon_console), ("config", icon_config),
                     ("guide", icon_guide), ("repair", icon_repair),
                     ("uninstall", icon_uninstall)):
        save_ico(fn(), name)


if __name__ == "__main__":
    main()
