#!/usr/bin/env python3
"""Crop only unobstructed native sRGB reference surfaces into 3× texture assets."""
from pathlib import Path
import struct, zlib, json
root = Path(__file__).resolve().parent.parent

def png(path, width, height, rgba):
    def chunk(kind, data): return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    scan=b''.join(b'\0'+rgba[y*width*4:(y+1)*width*4] for y in range(height))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,6,0,0,0))+chunk(b'sRGB',b'\0')+chunk(b'IDAT',zlib.compress(scan,9))+chunk(b'IEND',b''))

for name,second,rect in [('PaperReference',44,(90,1450,960,480)), ('MapCardReference',99,(510,1650,450,150)), ('PaperPreview1',65,(165,1440,150,240)), ('PaperPreview2',65,(585,1440,150,240)), ('PaperPreview3',65,(1041,1440,150,240))]:
    x,y,w,h=rect
    data=(root/f'.build/reference-colors/{second:03}.rgba').read_bytes()
    cropped=b''.join(data[((y+j)*1398+x)*4:((y+j)*1398+x+w)*4] for j in range(h))
    asset=root/f'Brewwww/Assets.xcassets/{name}.imageset'; asset.mkdir(parents=True,exist_ok=True)
    png(asset/f'{name}@3x.png',w,h,cropped)
    images=[{'filename':f'{name}@3x.png','idiom':'universal','scale':'3x'}]
    if (asset/f'{name}-Light@3x.png').exists():
        images[0]['appearances']=[{'appearance':'luminosity','value':'dark'}]
        images.insert(0,{'filename':f'{name}-Light@3x.png','idiom':'universal','scale':'3x'})
    (asset/'Contents.json').write_text(json.dumps({'images':images,'info':{'author':'xcode','version':1}},indent=2))
(root/'Brewwww/Assets.xcassets/Contents.json').write_text('{"info":{"author":"xcode","version":1}}')
