#!/usr/bin/env python3
"""移动端终端交互原型图渲染（PIL 直绘，无外部依赖）。

    python3 docs/prototypes/render.py    # → docs/prototypes/mobile-terminal-ux.png

配色取 lib/theme.dart 的 AppPalette 深色板与 settings.dart 的 githubDark 终端预设，
终端字号 / 行高 / 内边距与 SshTerminalView 的真实取值一致（13.5 / 1.45 / 10）。
原型只给人看布局与交互，不参与构建；脚本改坏了也只影响这张图。
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONT_MONO = ROOT / "assets/fonts/jetbrains_mono/JetBrainsMono-Regular.ttf"
FONT_MONO_BOLD = ROOT / "assets/fonts/jetbrains_mono/JetBrainsMono-Bold.ttf"
FONT_UI = Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc")
FONT_UI_BOLD = Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc")
CJK_SC = 2  # NotoSansCJK-*.ttc 里的简体中文面

# —— 配色（对齐 lib/theme.dart 与 TerminalPreset.githubDark）——
BG = (10, 12, 15)
FG = (214, 222, 231)
DIM = (110, 118, 129)
GREEN = (63, 185, 80)
BLUE = (88, 166, 255)
YELLOW = (210, 153, 34)
RED = (248, 81, 73)
CYAN = (57, 197, 207)
PANEL = (23, 27, 33)
ACCENT = (76, 141, 255)
HAIRLINE = (255, 255, 255, 26)
SHEET = (238, 240, 244)
INK = (28, 32, 38)
INK_DIM = (110, 118, 130)
KEYBOARD = (27, 31, 38)
KEYCAP = (52, 57, 66)
KEYCAP_DARK = (72, 78, 88)

S = 1.5  # 渲染倍率
W, H = 390, 844  # 手机逻辑尺寸（iPhone 14）
LINE_H = 19  # 终端行高：13.5pt × 1.45
TERM_TOP = 118
TERM_LEFT = 12
_cache: dict = {}


def px(v):
    return int(round(v * S))


def font(size, kind="ui", bold=False):
    key = (kind, size, bold)
    if key not in _cache:
        if kind == "mono":
            path = FONT_MONO_BOLD if bold else FONT_MONO
            _cache[key] = ImageFont.truetype(str(path), px(size))
        else:
            path = FONT_UI_BOLD if bold else FONT_UI
            _cache[key] = ImageFont.truetype(str(path), px(size), index=CJK_SC)
    return _cache[key]


def _runs(text):
    """按 CJK / 其余切段：内置等宽字体没有汉字，混排必须逐段换字体。"""
    out = []
    for ch in text:
        kind = "ui" if ord(ch) > 0x2E7F else "mono"
        if out and out[-1][0] == kind:
            out[-1][1] += ch
        else:
            out.append([kind, ch])
    return out


def measure(text, size, bold=False):
    return sum(font(size, k, bold).getlength(s) for k, s in _runs(text))


class Screen:
    """一块手机屏幕：坐标一律写逻辑像素，内部乘 S。"""

    def __init__(self):
        self.img = Image.new("RGB", (px(W), px(H)), BG)
        self.d = ImageDraw.Draw(self.img, "RGBA")

    def rect(self, x, y, w, h, fill=None, r=0, outline=None, width=1):
        box = [px(x), px(y), px(x + w), px(y + h)]
        if r:
            self.d.rounded_rectangle(
                box, radius=px(r), fill=fill, outline=outline, width=px(width)
            )
        else:
            self.d.rectangle(box, fill=fill, outline=outline, width=px(width))

    def dot(self, x, y, r, fill):
        self.d.ellipse([px(x - r), px(y - r), px(x + r), px(y + r)], fill=fill)

    def line(self, x1, y1, x2, y2, fill, width=1.4):
        self.d.line(
            [px(x1), px(y1), px(x2), px(y2)], fill=fill, width=px(width), joint="curve"
        )

    def text(self, x, y, s, size=13, fill=FG, bold=False, align="left"):
        """混排文本；y 是垂直中心。align=middle / right 时 x 为中心 / 右边界。"""
        total = measure(s, size, bold)
        if align == "middle":
            x -= total / S / 2
        elif align == "right":
            x -= total / S
        for kind, run in _runs(s):
            f = font(size, kind, bold)
            self.d.text((px(x), px(y)), run, font=f, fill=fill, anchor="lm")
            x += f.getlength(run) / S

    # —— 复合件 ——
    def chip(self, x, y, label, size=12, pad=10, h=30, active=False, w=None):
        width = w if w else measure(label, size, active) / S + pad * 2
        self.rect(
            x,
            y,
            width,
            h,
            r=h / 2.4,
            fill=ACCENT if active else (255, 255, 255, 16),
            outline=None if active else HAIRLINE,
        )
        self.text(
            x + width / 2,
            y + h / 2,
            label,
            size,
            (255, 255, 255) if active else FG,
            bold=active,
            align="middle",
        )
        return width

    def badge(self, x, y, n):
        """标注序号：实心主色圆点，压在原型图上。"""
        self.dot(x, y, 12, ACCENT)
        self.text(x, y, str(n), 12, (255, 255, 255), bold=True, align="middle")


# —— 通用结构 ——
def status_bar(s):
    s.text(34, 30, "9:41", 13.5, FG, bold=True)
    s.rect(145, 12, 100, 26, r=13, fill=(0, 0, 0))  # 灵动岛
    for i, h in enumerate((4, 6, 8, 10)):
        s.rect(302 + i * 6, 32 - h, 4, h, r=1, fill=FG)
    for i in range(3):
        s.d.arc(
            [px(332 - i * 3), px(24 - i * 3), px(348 + i * 3), px(40 + i * 3)],
            start=225,
            end=315,
            fill=FG,
            width=px(1.4),
        )
    s.rect(356, 24, 22, 12, r=3, outline=FG, width=1)
    s.rect(357.5, 25.5, 15, 9, r=2, fill=GREEN)
    s.rect(379, 27.5, 2, 5, r=1, fill=FG)


def immersive_header(s):
    """① 沉浸式头部：取代 AppBar，轻点唤出、3 秒自动淡出。"""
    s.rect(12, 52, 366, 46, r=15, fill=(23, 27, 33, 238), outline=HAIRLINE)
    s.line(34, 68, 27, 75, FG, 2)
    s.line(27, 75, 34, 82, FG, 2)
    s.dot(54, 75, 4, GREEN)
    s.text(64, 75, "web-prod-01", 14, FG, bold=True)
    s.chip(258, 63, "2 个会话", 11.5, pad=9, h=24)  # ② 会话胶囊
    for i in range(3):
        s.dot(345 + i * 8, 75, 2, FG)


def key_bar(s, y=464, ctrl_locked=True, collapsed=False):
    """③④ 快捷键条：Esc / Tab / Ctrl / Alt / 方向键，可折叠。"""
    if collapsed:
        s.chip(W / 2 - 62, y, "⌃  快捷键", 12, h=32, w=124)
        return
    s.rect(8, y, 374, 46, r=14, fill=(23, 27, 33, 246), outline=HAIRLINE)
    x = 16
    for label, w, active in (
        ("esc", 34, False),
        ("tab", 34, False),
        ("ctrl", 44, ctrl_locked),
        ("alt", 34, False),
        ("←", 30, False),
        ("↑", 30, False),
        ("↓", 30, False),
        ("→", 30, False),
    ):
        s.chip(x, y + 7, label, 12.5, w=w, h=32, active=active)
        x += w + 5
    s.chip(334, y + 7, "⌄", 13, w=32, h=32)


def keyboard(s):
    """软键盘示意：候选词条 + 四行键帽，只为让人看出「键盘弹起」。"""
    top = 514
    s.rect(0, top, W, H - top, fill=KEYBOARD)
    s.line(0, top, W, top, (255, 255, 255, 18), 1)
    for i, word in enumerate(("日志", "服务", "重启")):
        s.text(65 + i * 130, top + 20, word, 14, FG)
    for i in range(2):
        s.line(130 + i * 130, top + 10, 130 + i * 130, top + 30, (255, 255, 255, 20), 1)
    kw, gap = 31, 5.5
    for r, row in enumerate(("qwertyuiop", "asdfghjkl", "zxcvbnm")):
        y = 556 + r * 56
        start = 16 + (358 - (len(row) * kw + (len(row) - 1) * gap)) / 2
        for i, ch in enumerate(row):
            s.rect(start + i * (kw + gap), y, kw, 44, r=7, fill=KEYCAP)
            s.text(start + i * (kw + gap) + kw / 2, y + 22, ch, 12.5, FG, align="middle")
        if r == 2:
            s.rect(start - 46, y, 40, 44, r=7, fill=KEYCAP_DARK)
            s.rect(start + len(row) * (kw + gap) + 6, y, 40, 44, r=7, fill=KEYCAP_DARK)
    y = 556 + 3 * 56
    s.rect(24, y, 44, 44, r=7, fill=KEYCAP_DARK)
    s.text(46, y + 22, "123", 11.5, FG, align="middle")
    s.rect(74, y, 34, 44, r=7, fill=KEYCAP_DARK)
    s.rect(114, y, 158, 44, r=7, fill=KEYCAP_DARK)
    s.text(193, y + 22, "空格", 11.5, FG, align="middle")
    s.rect(278, y, 88, 44, r=7, fill=KEYCAP_DARK)
    s.text(322, y + 22, "换行", 11.5, FG, align="middle")


def home_indicator(s):
    s.rect(W / 2 - 70, 820, 140, 5, r=2.5, fill=(255, 255, 255, 90))


P = "cheng@web-prod-01"
URL = "https://web-prod-01:8080/health"


def shell_lines():
    """一段真实感的输出；行宽控制在 45 列内（390pt 屏、13.5 号等宽）。"""

    def cmd(c):
        return [(f"{P}:~$ ", GREEN), (c, FG)]

    return [
        cmd("ls -la"),
        ("total 32", DIM),
        ("drwxr-xr-x  6 cheng cheng 4096 Sep 21 10:09 .", FG),
        ("drwxr-xr-x 12 root  root  4096 Sep 18 17:35 ..", FG),
        ("-rw-r--r--  1 cheng cheng  312 Sep 21 09:58 deploy.sh", FG),
        ("drwxr-xr-x  3 cheng cheng 4096 Sep 20 15:43 logs", FG),
        cmd("docker compose ps"),
        ("NAME    SERVICE  STATUS   PORTS", DIM),
        ("web     web      running  0.0.0.0:8080->80/tcp", FG),
        ("redis   cache    running  6379/tcp", FG),
        cmd("tail -f logs/app.log"),
        ("[10:09:12] INFO  listening on :8080", CYAN),
        ("[10:09:13] INFO  connected to redis", CYAN),
        ("[10:09:14] WARN  slow query 812ms", YELLOW),
        ("[10:09:15] ERROR upstream timeout, retry", RED),
    ]


def term_lines(s, lines, top=TERM_TOP):
    y = top
    for line in lines:
        x = TERM_LEFT
        for text, color in line if isinstance(line, list) else [line]:
            s.text(x, y, text, 13.5, color)
            x += measure(text, 13.5) / S
        y += LINE_H
    return y


def frame_terminal():
    """屏 1：全屏终端 + 快捷键条 + 软键盘弹起。"""
    s = Screen()
    status_bar(s)
    immersive_header(s)
    term_lines(s, shell_lines())
    prompt_y = TERM_TOP + len(shell_lines()) * LINE_H + 6
    s.text(TERM_LEFT, prompt_y, f"{P}:~$ ", 13.5, GREEN)
    s.rect(
        TERM_LEFT + measure(f"{P}:~$ ", 13.5) / S, prompt_y - 8, 8, 16, fill=GREEN
    )
    s.chip(262, 398, "↓  最新", 11.5, h=30, w=92)  # ⑤ 回到最新输出
    key_bar(s)
    keyboard(s)
    home_indicator(s)
    s.badge(108, 36, 1)  # 指头部
    s.badge(272, 36, 2)  # 指会话胶囊
    s.badge(30, prompt_y + 22, 3)
    s.badge(104, prompt_y + 22, 4)
    s.badge(242, 413, 5)
    s.badge(352, 440, 6)
    return s.img


def frame_selection():
    """屏 2：长按选择 + 上下文菜单（触屏可达）。"""
    s = Screen()
    status_bar(s)
    immersive_header(s)
    lines = shell_lines()[:13]
    lines += [
        [(f"{P}:~$ ", GREEN), ("tail -n2 app.log", FG)],
        [("check ", FG), (URL, BLUE)],
        ("HTTP/2 200", FG),
        ("content-type: application/json", DIM),
        ("date: Sun, 21 Sep 2025 10:09:15 GMT", DIM),
    ]
    term_lines(s, lines)
    link_y = TERM_TOP + 14 * LINE_H
    url_x = TERM_LEFT + measure("check ", 13.5) / S
    url_w = measure(URL, 13.5) / S
    s.rect(url_x, link_y - 9, url_w, 18, fill=(76, 141, 255, 90))  # ⑦ 选区
    s.line(url_x, link_y + 9, url_x + url_w, link_y + 9, BLUE, 1.2)
    s.dot(url_x, link_y + 10, 6.5, ACCENT)  # 选区手柄
    s.dot(url_x + url_w, link_y + 10, 6.5, ACCENT)
    menu_y = link_y + 26  # ⑧ 长按菜单
    s.rect(84, menu_y, 222, 206, r=14, fill=(28, 33, 40), outline=HAIRLINE)
    for i, item in enumerate(("复制", "粘贴", "全选", "打开链接", "搜索终端输出")):
        iy = menu_y + 8 + i * 38
        if i == 3:
            s.line(96, iy - 4, 294, iy - 4, (255, 255, 255, 22), 1)
        s.text(104, iy + 19, item, 14, ACCENT if i == 3 else FG)
    s.rect(120, 700, 150, 34, r=17, fill=(28, 33, 40), outline=HAIRLINE)
    s.dot(142, 717, 6.5, GREEN)
    s.text(156, 717, "已复制选中内容", 12.5, FG)  # ⑨ 轻提示
    key_bar(s, y=760, collapsed=True)
    home_indicator(s)
    s.badge(334, link_y - 16, 7)
    s.badge(366, link_y - 16, 10)
    s.badge(60, menu_y + 19, 8)
    s.badge(96, 717, 9)
    return s.img


def frame_sessions():
    """屏 3：会话与命令片段面板（移动端补齐多会话入口）。"""
    s = Screen()
    status_bar(s)
    immersive_header(s)
    term_lines(s, shell_lines()[:12])
    s.rect(0, 0, W, H, fill=(0, 0, 0, 140))  # 遮罩
    s.rect(0, 380, W, H - 380, r=26, fill=PANEL)
    s.rect(170, 392, 50, 4.5, r=2, fill=(255, 255, 255, 60))
    s.text(20, 426, "会话", 13, DIM, bold=True)
    s.text(370, 426, "＋ 新建", 12.5, ACCENT, align="right")
    for i, (label, current) in enumerate((("会话 1", False), ("会话 2", True))):
        y = 452 + i * 50
        if current:
            s.rect(12, y, 366, 46, r=12, fill=(255, 255, 255, 12))
        s.dot(32, y + 20, 4.5, GREEN)
        s.text(48, y + 20, "web-prod-01", 14, FG)
        s.text(146, y + 20, label, 13, DIM)
        if current:
            s.chip(276, y + 8, "当前", 11, pad=9, h=22, active=True)
    s.line(20, 556, 370, 556, HAIRLINE, 1)
    s.text(20, 588, "命令片段", 13, DIM, bold=True)
    for i, cmd in enumerate(
        (
            "tail -f logs/app.log",
            "docker compose ps",
            "git status",
            "systemctl restart web",
            "journalctl -u web",
            "df -h",
        )
    ):
        x = 20 + (i % 2) * 182
        y = 610 + (i // 2) * 46
        w = min(174, measure(cmd, 11.5) / S + 24)
        s.rect(x, y, w, 36, r=10, fill=(255, 255, 255, 14), outline=HAIRLINE)
        s.text(x + 12, y + 18, cmd, 11.5, FG)
    home_indicator(s)
    s.badge(200, 427, 11)
    s.badge(206, 589, 12)
    return s.img


def phone(screen):
    """套机身：外框 + 屏幕圆角。"""
    pad = 12
    frame = Image.new("RGBA", (screen.width + pad * 2, screen.height + pad * 2))
    ImageDraw.Draw(frame).rounded_rectangle(
        [0, 0, frame.width - 1, frame.height - 1], radius=px(52), fill=(22, 25, 30)
    )
    mask = Image.new("L", screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, screen.width - 1, screen.height - 1], radius=px(40), fill=255
    )
    frame.paste(screen, (pad, pad), mask)
    return frame


LEGEND = (
    "沉浸式头部：进终端收起 AppBar，轻点唤出",
    "会话胶囊：点开就是会话列表",
    "快捷键条：Esc / Tab / Ctrl / Alt / 方向键",
    "粘滞 Ctrl：点一次只作用于下一个按键",
    "回到最新输出；双指捏合缩放字号",
    "键条贴键盘上沿，弹起时终端行数重排",
    "长按选词 / 拖拽手柄，边缘自动滚动",
    "长按菜单：复制 / 粘贴 / 全选 / 打开链接",
    "选中即复制（默认开），轻提示已复制",
    "触屏点链接直达，去掉 Cmd / Ctrl 门禁",
    "会话切换 + 新建会话，目标 ≥ 44dp",
    "片段一键发往当前会话，长按可编辑",
)


def main():
    shots = [phone(f()) for f in (frame_terminal, frame_selection, frame_sessions)]
    gap, margin, top = 46, 46, 178
    pw, ph = shots[0].size
    width = margin * 2 + len(shots) * pw + gap * (len(shots) - 1)
    height = top + ph + 46 + 4 * 44 + 30
    sheet = Image.new("RGB", (width, height), SHEET)

    d = ImageDraw.Draw(sheet, "RGBA")
    d.text((margin, 52), "NoShell 移动端终端 · 交互原型", font=font(30, bold=True), fill=INK, anchor="lm")
    d.text(
        (margin, 100),
        "390 × 844 逻辑像素 · 配色取 AppPalette 深色板与 GitHub Dark 终端预设 · 终端 13.5pt / 行高 1.45",
        font=font(14),
        fill=INK_DIM,
        anchor="lm",
    )
    d.line([margin, 138, width - margin, 138], fill=(0, 0, 0, 34), width=2)

    shadow = Image.new("RGBA", sheet.size)
    sd = ImageDraw.Draw(shadow)
    for i in range(len(shots)):
        x = margin + i * (pw + gap)
        sd.rounded_rectangle(
            [x + 4, top + 16, x + pw - 4, top + ph + 4], radius=px(52), fill=(16, 21, 31, 74)
        )
    sheet = Image.alpha_composite(sheet.convert("RGBA"), shadow.filter(ImageFilter.GaussianBlur(px(10)))).convert("RGB")
    for i, shot in enumerate(shots):
        sheet.paste(shot, (margin + i * (pw + gap), top), shot)

    d = ImageDraw.Draw(sheet, "RGBA")
    col_w = (width - margin * 2) // 3
    for i, item in enumerate(LEGEND):
        cx = margin + (i % 3) * col_w
        cy = top + ph + 62 + (i // 3) * 44
        d.ellipse([cx, cy - 15, cx + 30, cy + 15], fill=ACCENT)
        d.text((cx + 15, cy), str(i + 1), font=font(13, bold=True), fill=(255, 255, 255), anchor="mm")
        d.text((cx + 42, cy), item, font=font(13.5), fill=INK, anchor="lm")

    out = Path(__file__).with_name("mobile-terminal-ux.png")
    sheet.save(out, optimize=True)
    print(f"{out}  {sheet.width}×{sheet.height}")


if __name__ == "__main__":
    assert FONT_MONO.exists() and FONT_UI.exists(), "字体缺失：检查 assets/fonts 与 Noto Sans CJK"
    main()
    assert Path(__file__).with_name("mobile-terminal-ux.png").stat().st_size > 0
