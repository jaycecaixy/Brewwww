#!/usr/bin/env python3
"""Publish measured swatches alongside native-pixel evidence crops."""
from pathlib import Path
import json, html, struct, zlib
root=Path(__file__).resolve().parent.parent
report=json.loads((root/'设计取色/reference-colors.json').read_text())
# A rough ROI does not establish semantic ownership of a road/water pixel.
report['measurements']=[m for m in report['measurements'] if m['token'] not in ['mapRoad','mapWater','stampEmptyOutline']]
report['limitations']=['HEVC 解码后的 sRGB 显示色，不等同原始设计文件色值。','渐变/纹理仅给代表色与分位范围；实际纹理已另行提取。','照片内容与抗锯齿文字的取色受压缩与背景混合影响。','地图服务底图与系统界面只记录参考，不由应用硬编码。','录屏没有完整展示的三种纸张及其他状态无法确认。']
(root/'设计取色/reference-colors.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
out=root/'设计取色';(out/'samples').mkdir(exist_ok=True)
def png(path,w,h,data):
    def chunk(t,b): return struct.pack('>I',len(b))+t+b+struct.pack('>I',zlib.crc32(t+b)&0xffffffff)
    rows=b''.join(b'\0'+data[y*w*4:(y+1)*w*4] for y in range(h))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'sRGB',b'\0')+chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b''))
rows=[];md=[];cache={}
for m in report['measurements']:
    second=m['frame'];x,y,w,h=m['pixelRect']
    if second not in cache:cache[second]=(root/f'.build/reference-colors/{second:03}.rgba').read_bytes()
    data=cache[second]; crop=b''.join(data[((y+j)*1398+x)*4:((y+j)*1398+x+w)*4] for j in range(h))
    png(out/f"samples/{m['token']}.png",w,h,crop)
    status='系统参考' if m['kind']=='system' else '底图参考' if m['kind']=='map' else '纹理/渐变代表色' if m['kind'] in ['texture','gradient'] else '文字/图案近似' if m['dominantFraction']<.12 else '平面/主色'
    rows.append(f'''<article><div class="swatch" style="background:{m['hex']}"></div><h3>{html.escape(m['label'])}</h3><code>{m['hex']}</code><p>{second}s · {status}</p><a href="samples/{m['token']}.png"><img src="samples/{m['token']}.png" alt="原像素采样区域"></a><small>{m['token']}<br>原始像素矩形 {m['pixelRect']}<br>P10 {m['p10']} / P90 {m['p90']}</small></article>''')
    md.append(f"|{m['label']}|`{m['hex']}`|{second}s|{status}|")
intro='''# 第一段录屏取色复核

基于 ScreenRecording_10-25-2026 23-04-27_1.MP4（126.468 秒），提取 23 个原始分辨率画面（1398×2034），转换 CoreMedia709 → sRGB 后取样。所有坐标与通道值可在 reference-colors.json 复查，palette.html 展示每个取样区域的无损原像素。

工程已应用：纸张底纹、面板/细边、日历格/星期/数字、强调色、圆形按钮与导航选中态、表单、设置开关、照片夹分区渐变、拍立得边框/文字、照片页背景、地图信息卡/标记/按钮、印章配色。照片夹以多色渐变重建，照片页背景以三段渐变近似，均不宣称纹理或材质像素级完全一致。

纸张主背景、地图卡片纹理取自无控件区域，按原生 3× 比例平铺；外观页可见的前三种纸张也单独提取。录屏中未完整展示的后三种纸张暂共用主背景，无法据此推断原始素材。地图使用 MapKit，原应用为高德，底图配色与图形仍有差异。键盘、照片选择器、系统弹窗由系统绘制。

这是录屏的解码显示色。视频压缩、文字抗锯齿、照片及透明材质会产生颜色范围，不能反推出唯一的原始设计色值。低主色占比的文字与插画标为近似，禁止当成经过设计文件验证的色值。

|组件|sRGB|录屏时间|类型|
|---|---|---|---|
'''
(out/'取色说明.md').write_text(intro+'\n'.join(md)+'\n\n复现：先编译运行 scripts/extract-reference-frames.swift，再运行 scripts/sample-reference-colors.py、scripts/export-reference-textures.py、scripts/write-color-report.py。\n')
(out/'palette.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Brewwww 录屏取色</title><style>body{font:16px system-ui;background:#191917;color:#e7e5de;padding:28px;max-width:1400px;margin:auto}h1{font-size:28px}header{max-width:900px;line-height:1.8}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:16px}article{background:#292825;border:1px solid #494740;border-radius:16px;padding:16px;overflow:hidden}h3{font-size:16px}p,small{color:#bbb5aa}.swatch{height:70px;border:1px solid #7775;border-radius:8px}img{display:block;max-width:100%;height:72px;object-fit:contain;object-position:left;margin:16px 0;image-rendering:auto}code{font-size:20px}small{line-height:1.7;overflow-wrap:anywhere}</style><header><h1>第一段录屏 · 组件取色复核</h1><p>23 个原分辨率画面，CoreMedia709 → sRGB。每张卡片下方展示实际采样像素，点击可看原尺寸。纹理与渐变显示代表色，P10/P90 表示各 RGB 通道的范围。文字、图案与视频压缩存在混色，不能据此宣称还原了原始设计文件。</p><p>应用拥有的主要颜色已接入工程。地图底图与系统控件仅作参考；未展示的状态仍待补充。照片夹渐变、照片页背景仍为近似重建。</p></header><main>'''+''.join(rows)+'</main></html>')
print(len(rows),'samples published')
