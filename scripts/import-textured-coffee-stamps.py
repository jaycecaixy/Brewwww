"""Import the ImageGen originals verbatim; produce contact sheets for visual QA.
No retouching, background removal, filtering or colour changes are applied to app assets.
Run with the bundled Python (Pillow). Generation prompts and source paths are in the manifest.
"""
from pathlib import Path
import json, shutil, re
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[1]
manifest=ROOT/'设计取色/印章手绘/imagegen-manifest.json'
items=json.loads(manifest.read_text())
model=(ROOT/'Brewwww/CaffeTogether.swift').read_text()
enum_head=model.split('enum CaffeTogetherStamp',1)[1].split('var id:',1)[0]
ids=[token.strip() for line in re.findall(r'^\s*case (.+)$',enum_head,re.M) for token in line.split(',')]
assert len(ids)==28 and len(set(ids))==28
assert len({item['id'] for item in items})==len(items)
items.sort(key=lambda item:ids.index(item['id']))
names=re.findall(r'"([^"]+)"',model.split('let names = [',1)[1].split(']',1)[0])
assert len(names)==28
titles=dict(zip(ids,names))
assets=ROOT/'Brewwww/Assets.xcassets'
for item in items:
    name=f'Caffe{item["group"]}_{item["id"]}'
    folder=assets/f'{name}.imageset'
    source=Path(item.get('workspaceOriginal',item['path']))
    if not source.is_absolute():source=ROOT/source
    if not source.exists():raise FileNotFoundError(source)
    with Image.open(source) as image:
        assert image.mode=='RGBA',f'{name}: expected original transparency'
        assert image.getextrema()[3][0]==0,f'{name}: no transparent pixels'
    folder.mkdir(exist_ok=True)
    destination=folder/f'{name}@3x.png'
    if source.resolve()!=destination.resolve():shutil.copy2(source,destination)
    (folder/'Contents.json').write_text(json.dumps({'images':[{'filename':f'{name}@3x.png','idiom':'universal','scale':'3x'}],'info':{'author':'xcode','version':1}},indent=2)+'\n')
    # The replaced PDF is no longer referenced by this image set.
    for old in folder.glob('*.pdf'):old.unlink()
    for old in folder.glob('*.png'):
        if old.name != f'{name}@3x.png':old.unlink()
    item['workspaceOriginal']=str((folder/f'{name}@3x.png').relative_to(ROOT))
manifest.write_text(json.dumps(items,ensure_ascii=False,indent=2)+'\n')
font=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',21)
small=ImageFont.truetype('/System/Library/Fonts/Supplemental/Songti.ttc',19)
# Preview-only composition from the original RGBA artwork. App assets remain untouched.
preview=ROOT/'预览/咖啡手绘印章-质感版';preview.mkdir(exist_ok=True)
for group in ['Together','Explore']:
    subset=[i for i in items if i['group']==group]
    columns=5 if group=='Together' else 4
    sheet=Image.new('RGB',(1200,1160 if group=='Together' else 650),'#F5F0E7');d=ImageDraw.Draw(sheet)
    d.text((35,28),f'CAFFE {group.upper()} / TEXTURED PASTEL',font=font,fill='#655940')
    d.text((35,62),'5 cups per stamp' if group=='Together' else '3 independent cafe cups per stamp',font=small,fill='#99805E')
    for index,item in enumerate(subset):
        source=ROOT/item['workspaceOriginal'];art=Image.open(source).convert('RGBA');art.thumbnail((200,200),Image.Resampling.LANCZOS)
        x=(1200-columns*236)//2+(index%columns)*236;y=105+(index//columns)*255
        sheet.paste(art,(x+(200-art.width)//2,y+(200-art.height)//2),art)
        d.text((x+100,y+208),f'{(index+1)*(5 if group=="Together" else 3)} 杯 · {titles[item["id"]]}',anchor='mt',font=small,fill='#8C704D')
    sheet.save(preview/f'Caffe-{group}-{len(subset)}枚.png')
print(f'Imported {len(items)} untouched originals; previews in {preview}')
