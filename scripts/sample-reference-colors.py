#!/usr/bin/env python3
"""Measure native video frames after explicit CoreMedia709 → sRGB conversion."""
import argparse
from collections import Counter
import json
from pathlib import Path
from statistics import median

# Rectangles use Duo logical points; the original recording is exactly 3×.
# Each sample is deliberately inside a surface or glyph, away from AA edges.
SAMPLES = [
    ("paperBase", "主背景纸张基色", 44, [40, 470, 300, 160], "texture", "all"),
    ("paperHome", "首页纸张背景复核", 1, [20, 625, 330, 30], "texture", "all"),
    ("textPrimary", "主标题/主文字", 1, [165, 34, 62, 32], "text", "bright"),
    ("textSecondary", "日期与次级文字", 1, [120, 74, 150, 15], "text", "bright"),
    ("calendarPanel", "日历面板", 1, [35, 155, 125, 38], "solid", "all"),
    ("summaryPanel", "本月汇总面板", 1, [34, 483, 100, 9], "solid", "all"),
    ("calendarDay", "普通日期格", 1, [86, 227, 14, 9], "solid", "all"),
    ("calendarSelected", "有记录的日期格", 1, [32, 392, 40, 45], "solid", "gold"),
    ("calendarWeekday", "星期表头文字", 1, [40, 133, 310, 15], "text", "muted"),
    ("calendarNumber", "日期数字", 1, [45, 238, 15, 15], "text", "bright"),
    ("summaryCaption", "汇总次级文字", 1, [40, 565, 100, 14], "text", "muted"),
    ("controlFill", "圆形按钮底色", 1, [400, 225, 38, 38], "solid", "dark"),
    ("controlGlyph", "按钮/未选中图标", 1, [405, 230, 28, 29], "text", "muted"),
    ("modeButtonFill", "M/W 按钮底色复核", 1, [400, 279, 38, 38], "solid", "dark"),
    ("navigationFill", "竖向导航底色", 1, [411, 447, 14, 14], "solid", "all"),
    ("navigationSelected", "导航选中底板", 1, [409, 390, 19, 10], "solid", "all"),
    ("accentGlyph", "选中杯子图标", 1, [405, 400, 28, 30], "text", "gold"),
    ("plusFill", "新增按钮底色", 1, [400, 590, 38, 38], "solid", "dark"),
    ("plusGlyph", "新增加号", 1, [407, 600, 24, 26], "text", "gold"),
    ("folderBack", "照片夹后袋", 1, [255, 533, 9, 27], "gradient", "all"),
    ("folderFrontLeft", "照片夹前袋左侧", 1, [267, 550, 12, 14], "gradient", "all"),
    ("folderFrontCenter", "照片夹前袋中部", 1, [309, 552, 12, 14], "gradient", "all"),
    ("folderFrontRight", "照片夹前袋右侧", 1, [356, 552, 9, 14], "gradient", "all"),
    ("folderFrontBottom", "照片夹前袋底部", 1, [302, 585, 30, 5], "gradient", "all"),
    ("folderTab", "照片夹上方凸片", 1, [338, 525, 14, 5], "gradient", "all"),
    ("folderPhotoGold", "照片夹前照片边框", 1, [263, 490, 5, 18], "solid", "gold"),
    ("folderPhotoWhite", "照片夹后照片白边", 1, [350, 486, 11, 4], "solid", "white"),
    ("albumTop", "照片页背景上方", 24, [20, 30, 85, 35], "gradient", "all"),
    ("albumMiddle", "照片页背景左侧中部", 24, [15, 270, 35, 80], "gradient", "all"),
    ("albumBottom", "照片页背景下方", 24, [70, 590, 280, 50], "gradient", "all"),
    ("albumControlFill", "照片页圆形按钮", 24, [400, 225, 38, 38], "solid", "dark"),
    ("photoFrameTop", "拍立得边框上部", 24, [82, 188, 210, 12], "solid", "all"),
    ("photoFrameBottom", "拍立得边框底部", 24, [90, 487, 190, 8], "solid", "all"),
    ("photoFrameText", "拍立得店铺文字", 24, [88, 452, 155, 16], "text", "ink"),
    ("photoFrameCaption", "拍立得日期文字", 24, [88, 470, 120, 13], "text", "captionInk"),
    ("formPanel", "记录表单面板", 5, [60, 376, 180, 10], "solid", "all"),
    ("formText", "记录表单文字", 5, [80, 355, 170, 21], "text", "bright"),
    ("formPlaceholder", "表单箭头与星标", 5, [329, 620, 20, 24], "text", "muted"),
    ("confirmFill", "保存确认按钮", 5, [400, 280, 38, 38], "solid", "gold"),
    ("confirmGlyph", "保存确认勾号", 5, [405, 284, 28, 28], "text", "white"),
    ("settingsPanel", "设置行面板", 44, [55, 105, 200, 10], "solid", "all"),
    ("settingsText", "开启项文字", 44, [40, 211, 100, 20], "text", "bright"),
    ("settingsMuted", "关闭项文字", 44, [40, 123, 180, 20], "text", "muted"),
    ("toggleOn", "开关开启轨道", 44, [308, 216, 11, 10], "solid", "gold"),
    ("toggleOff", "开关关闭轨道", 44, [326, 128, 10, 9], "solid", "bright"),
    ("toggleThumb", "开关滑块", 44, [331, 220, 4, 4], "solid", "white"),
    ("settingsPanelBorder", "设置行细描边", 44, [100, 98, 190, 1.3], "solid", "all"),
    ("appearanceSelected", "外观选中卡背景", 65, [222, 133, 130, 10], "solid", "gold"),
    ("appearanceUnselected", "外观未选卡背景", 65, [27, 137, 120, 10], "solid", "all"),
    ("appearancePagination", "分页未选圆点", 65, [161, 337, 4, 4], "solid", "all"),
    ("paperPreviewOne", "第一种纸张预览", 65, [55, 480, 50, 80], "texture", "all"),
    ("paperPreviewTwo", "第二种纸张预览", 65, [195, 480, 50, 80], "texture", "all"),
    ("paperPreviewThree", "第三种纸张预览", 65, [347, 480, 50, 80], "texture", "all"),
    ("stampOrange", "店铺印章橙色", 81, [210, 140, 135, 145], "text", "orange"),
    ("stampPink", "纪念印章粉色", 81, [45, 330, 135, 83], "text", "pink"),
    ("stampGold", "印章金色文字", 81, [50, 176, 130, 85], "text", "gold"),
    ("stampEmptyOutline", "印章空位虚线", 81, [221, 322, 115, 112], "text", "muted"),
    ("mapPanel", "地图店铺信息卡", 99, [170, 550, 150, 50], "texture", "all"),
    ("mapPin", "地图打卡标记橙色", 99, [185, 275, 75, 82], "solid", "orange"),
    ("mapLand", "地图陆地区域", 99, [60, 130, 15, 20], "map", "all"),
    ("mapWater", "地图水域", 99, [355, 250, 15, 25], "map", "all"),
    ("mapRoad", "地图道路", 99, [150, 180, 20, 20], "map", "all"),
    ("mapControlFill", "地图圆形按钮", 99, [400, 225, 38, 38], "solid", "dark"),
    ("mapNavigationFill", "地图导航底色", 99, [409, 437, 14, 16], "solid", "all"),
    ("mapNavigationSelected", "地图导航选中底色", 99, [409, 557, 17, 8], "solid", "all"),
    ("systemPickerBackground", "系统照片选择器底色", 110, [25, 14, 290, 20], "system", "all"),
    ("systemAlertBackground", "系统弹窗底色", 50, [85, 110, 150, 10], "system", "all"),
    ("systemKeyboardKey", "系统键盘按键", 50, [46, 505, 12, 7], "system", "all"),
]


def accepted(color, kind):
    r, g, b = color
    if kind == "bright": return min(color) > 140 and max(color) - min(color) < 65
    if kind == "white": return min(color) > 225
    if kind == "muted": return min(color) > 85 and max(color) < 220 and max(color) - min(color) < 65
    if kind == "gold": return r > 145 and 95 < g < 225 and b < 185 and r - g > 22 and g - b > 16
    if kind == "dark": return max(color) < 125
    if kind == "ink": return r < 70 and g < 45 and b < 30
    if kind == "captionInk": return 60 < r < 140 and 35 < g < 105 and b < 70
    if kind == "orange": return r > 120 and 30 < g < 150 and b < 95 and r - g > 45
    if kind == "pink": return r > 135 and 65 < g < 180 and 60 < b < 170 and r - g > 28 and abs(g - b) < 40
    return True


def quantile(values, q):
    values = sorted(values)
    return values[round((len(values) - 1) * q)]


def hex_color(rgb):
    return "#" + "".join(f"{v:02X}" for v in rgb)


def measure(data, width, rect, kind, selection):
    x, y, w, h = [round(v * 3) for v in rect]
    colors = []
    for row in range(y, y + h):
        start = (row * width + x) * 4
        for column in range(w):
            i = start + column * 4
            c = tuple(data[i:i + 3])
            if accepted(c, selection): colors.append(c)
    if not colors: raise ValueError(f"No matching pixels: {rect} {selection}")
    channels = list(zip(*colors))
    median_rgb = [int(median(c)) for c in channels]
    dominant, count = Counter(colors).most_common(1)[0]
    if kind in ("texture", "gradient", "map"):
        representative = median_rgb
    elif count / len(colors) >= 0.12:
        representative = list(dominant)
    else:
        cluster = Counter(tuple(v // 4 for v in c) for c in colors).most_common(1)[0][0]
        members = [c for c in colors if tuple(v // 4 for v in c) == cluster]
        representative = [int(median(c)) for c in zip(*members)]
    return dict(rgb=representative, hex=hex_color(representative), median=median_rgb,
                p10=[quantile(c, .1) for c in channels], p90=[quantile(c, .9) for c in channels],
                dominant=list(dominant), dominantFraction=round(count / len(colors), 4), count=len(colors),
                pixelRect=[x, y, w, h])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames", default=".build/reference-colors")
    parser.add_argument("--output", default="设计取色/reference-colors.json")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    frames = root / args.frames
    metadata = json.loads((frames / "metadata.json").read_text())
    cached = {}
    results = []
    for token, label, second, rect, kind, selection in SAMPLES:
        if second not in cached: cached[second] = (frames / f"{second:03d}.rgba").read_bytes()
        data = cached[second]
        measured = measure(data, 1398, rect, kind, selection)
        results.append(dict(token=token, label=label, frame=second, rect=rect,
                            kind=kind, selection=selection, **measured))
        print(f"{token:25s} {measured['hex']} n={measured['count']:6d} mode={measured['dominantFraction']:.2f} {label}")
    report = dict(source=metadata["source"], colorSpace="sRGB", scale=3, measurements=results)
    output = root / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__": main()
