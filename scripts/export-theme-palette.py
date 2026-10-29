#!/usr/bin/env python3
"""Publish the exact theme tokens used by SwiftUI, with their reference limits."""
from pathlib import Path
import html
import json
import re

root = Path(__file__).resolve().parent.parent
out = root / '设计取色'
source = (root / 'Brewwww/Design.swift').read_text()
tokens = [{'name': name, 'light': '#' + light, 'dark': '#' + dark}
          for name, light, dark in re.findall(
              r'static let (\w+) = adaptive\(light: 0x([0-9A-F]{6}), dark: 0x([0-9A-F]{6})\)', source)]
(out / 'theme-colors.json').write_text(json.dumps(tokens, ensure_ascii=False, indent=2) + '\n')
labels = dict(ink='纸张基色', text='主文字', panel='日历 / 表单面板', panelLight='普通日期格',
              muted='次级文字', gold='强调色', orange='店铺印章', weekday='星期',
              calendarNumber='日期数字', todayNumber='今天的日期数字', control='圆形按钮',
              icon='未选中图标', selection='导航选中底板', border='细描边', placeholder='占位文字',
              toggleOff='关闭的开关', souvenirPanel='纪念杯底板', folderBack='照片夹后袋',
              folderLeft='前袋左侧', folderCenter='前袋中央', folderRight='前袋右侧',
              folderBottom='前袋底部', folderTab='前袋凸片', albumTop='相册上方',
              albumMiddle='相册中部', albumBottom='相册下方', albumControl='相册按钮',
              mapPanel='地图卡片', mapControl='地图按钮', mapNavigation='地图导航', mapSelection='地图选中底板')
rows = ''.join(f'''<tr><th>{html.escape(labels.get(t['name'], t['name']))}<small>{t['name']}</small></th>
<td><i style="background:{t['light']}"></i><code>{t['light']}</code></td>
<td><i style="background:{t['dark']}"></i><code>{t['dark']}</code></td></tr>''' for t in tokens)
page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Brewwww 深浅色主题</title><style>
:root{color-scheme:light dark}body{font:16px system-ui;background:light-dark(#f8f7f0,#2b2a23);color:light-dark(#3c2723,#d3d0cb);max-width:1000px;margin:auto;padding:30px;line-height:1.7}
h1{font-size:28px}a{color:light-dark(#9d632b,#dcab70)}table{width:100%;border-collapse:collapse;margin:24px 0}th,td{text-align:left;padding:12px;border-bottom:1px solid #8884}small{display:block;opacity:.6;font-weight:400}i{display:inline-block;width:55px;height:35px;border-radius:8px;vertical-align:middle;margin-right:12px;outline:1px solid #8885}code{font-size:15px}nav{display:flex;gap:12px;flex-wrap:wrap}button{font:inherit;padding:8px 16px;border:1px solid #8886;border-radius:20px;cursor:pointer}header p{max-width:830px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin:24px 0}.pair figure{margin:0}.pair img{width:100%;border-radius:18px}.pair figcaption{text-align:center} @media(max-width:600px){body{padding:16px}i{width:25px;margin-right:6px}th,td{padding:8px;font-size:13px}code{font-size:12px}}
</style><header><h1>Brewwww · 两套主题</h1>
<p>默认跟随系统，可在「设置 → 外观 → 主题」选择浅色或深色。下表直接从工程的颜色定义生成；按钮改变此色板页面的外观。</p>
<nav><button onclick="document.documentElement.style.colorScheme='light dark'">跟随系统</button><button onclick="document.documentElement.style.colorScheme='light'">浅色</button><button onclick="document.documentElement.style.colorScheme='dark'">深色</button></nav>
<p>深色依据三段录屏；浅色依据三张印章截图。浅色日历、照片夹、相册及地图卡片没有直接参考，采用同一组奶油色与暖棕色适配。文字和印章的截图取色含压缩与抗锯齿，属于代表色。浅色纸张为截图中无控件区域的原像素。</p>
<p><a href="palette.html">深色原始取样证据</a> · <a href="light-reference-colors.json">浅色原始取样坐标</a> · <a href="深浅色主题.md">实现与验收说明</a></p></header>
<div class="pair"><figure><a href="../预览/主题-浅色-首页.png"><img src="../预览/主题-浅色-首页.png" alt="浅色首页实机模拟器截图"></a><figcaption>浅色</figcaption></figure><figure><a href="../预览/主题-深色-首页.png"><img src="../预览/主题-深色-首页.png" alt="深色首页实机模拟器截图"></a><figcaption>深色</figcaption></figure></div>
<table><thead><tr><th>组件</th><th>浅色</th><th>深色</th></tr></thead><tbody>''' + rows + '</tbody></table></html>'
(out / 'themes.html').write_text(page)
palette = out / 'palette.html'
original = palette.read_text()
banner = '<p id="dual-theme-link"><a href="themes.html" style="color:#DCAB70">查看深浅两套主题、系统切换与页面对照 →</a>（以下为深色录屏原始取样）</p>'
if 'id="dual-theme-link"' not in original:
    palette.write_text(original.replace('<header>', '<header>' + banner, 1))
print(f'Published {len(tokens)} dynamic theme tokens.')
