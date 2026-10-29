"""Historical vector study, superseded by ImageGen textured originals.
Use import-textured-coffee-stamps.py for the current app assets.
Run this study only with --historical-study to avoid replacing current artwork.
"""
import sys
if "--historical-study" not in sys.argv:
    raise SystemExit("Historical study only. Current artwork: import-textured-coffee-stamps.py")
from pathlib import Path
import json, re, math, random
rng=random.Random(2718)
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
ROOT=Path(__file__).resolve().parents[1]
INK='#806A59'; PALETTE=['#C48F79','#94A995','#91A6B2','#C5AB78','#B2A0B6']
c=None

def path(d, fill=None, stroke=INK, width=1.7, alpha=1):
    c.saveState(); c.setStrokeColor(HexColor(stroke or INK)); c.setLineWidth(width); c.setLineCap(1); c.setLineJoin(1)
    c.setStrokeAlpha(alpha); c.setFillAlpha(alpha)
    if fill: c.setFillColor(HexColor(fill))
    p=c.beginPath(); tokens=re.findall(r'[MLCZ]|-?\d*\.?\d+',d); i=0
    while i<len(tokens):
        op=tokens[i]; i+=1
        n={'M':2,'L':2,'C':6,'Z':0}[op]; v=list(map(float,tokens[i:i+n])); i+=n
        if op=='M': p.moveTo(*v)
        elif op=='L': p.lineTo(*v)
        elif op=='C': p.curveTo(*v)
        else: p.close()
    c.drawPath(p,stroke=int(stroke is not None),fill=int(fill is not None))
    if fill:
        # Fine, irregular hatching gives the pastel fills a coloured-pencil grain.
        c.saveState(); c.clipPath(p,stroke=0,fill=0); c.setStrokeColor(HexColor(INK)); c.setStrokeAlpha(.10); c.setLineWidth(.32)
        for y in range(18,128,3):
            for x in range(18,124,9):
                dx=rng.uniform(-1,1);dy=rng.uniform(-.8,.8)
                c.line(x+dx,y+dy,x+dx+6,y+dy-2)
        c.restoreState()
    if stroke:
        # A second, light pencil pass keeps outlines from feeling machine-perfect.
        c.translate(.32,-.24); c.setStrokeAlpha(.20); c.setLineWidth(.6)
        c.drawPath(p,stroke=1,fill=0)
    c.restoreState()
def ellipse(x,y,rx,ry,fill=None,stroke=INK,width=1.5):
    k=.552285
    path(f'M {x-rx} {y} C {x-rx} {y-ry*k} {x-rx*k} {y-ry} {x} {y-ry} C {x+rx*k} {y-ry} {x+rx} {y-ry*k} {x+rx} {y} C {x+rx} {y+ry*k} {x+rx*k} {y+ry} {x} {y+ry} C {x-rx*k} {y+ry} {x-rx} {y+ry*k} {x-rx} {y} Z',fill,stroke,width)
def line(d,col=INK,w=1.3):path(d,stroke=col,width=w)
def box(x,y,w,h,fill=None):path(f'M {x} {y} L {x+w} {y} L {x+w} {y+h} L {x} {y+h} Z',fill)
def flower(x,y,r,col):
    for a in range(5):
        a=a*math.pi*2/5; ellipse(x+math.cos(a)*r*.64,y+math.sin(a)*r*.64,r*.38,r*.38,col,None)
    ellipse(x,y,r*.22,r*.22,'#CEAD77',None)
def steam(x=64,y=37):
    line(f'M {x-8} {y} C {x-16} {y-7} {x-1} {y-10} {x-7} {y-18}',w=1, col='#B9A696')
    line(f'M {x+7} {y-2} C {x+1} {y-9} {x+16} {y-12} {x+10} {y-19}',w=1,col='#B9A696')
def handle(x=96,y=61):
    path(f'M {x} {y} C {x+28} {y-7} {x+26} {y+30} {x-2} {y+29} L {x-2} {y+22} C {x+16} {y+24} {x+18} {y} {x} {y+7} Z','#E1D2BD')
def saucer(y=108):
    ellipse(65,y,47,9,'#E8DECC'); line(f'M 28 {y+1} C 45 {y+9} 83 {y+9} 101 {y}',w=.8)
def mug(i):
    col=PALETTE[i%5]
    if i in [2,3,11,17]:
        # Traditional low, rounded cups on delicately drawn saucers.
        saucer(); handle(94,64)
        path('M 27 58 C 28 85 34 102 62 103 C 88 104 96 85 98 58 Z',col)
        ellipse(62.5,58,35.5,8,'#F4EBDD'); ellipse(63,59,29,4,'#A78366',None)
        if i==2:
            for x in [40,50,60,70,80]:line(f'M {x} 73 L {x+3} 91','#EDE2CF',1.3)
        elif i==3:
            flower(59,81,9,'#EFE2CE');flower(81,77,5,'#EFE2CE')
        elif i==11:
            line('M 33 79 C 52 85 75 85 91 78','#E8DBC6',3)
        else:
            for x in [44,58,72,86]:line(f'M {x} 72 C {x-7} 79 {x+7} 84 {x} 93','#F0E6D6',1.4)
        steam(62,40);return
    if i in [4,5,10,12,15,18]:
        # Travel vessels: lid, straight thermos, tumbler, straw and sports bottle.
        if i==18:
            path('M 51 32 L 78 32 L 80 46 C 89 50 92 59 92 68 L 89 112 C 80 119 50 119 41 112 L 39 68 C 39 55 44 49 50 46 Z',col)
            box(49,26,31,10,'#E8DECC');line('M 55 27 C 52 12 78 12 76 26',w=2)
            flower(65,81,10,'#E6E7D8');return
        if i==15:
            path('M 42 46 L 89 46 L 86 113 C 77 118 51 117 44 112 Z',col)
            ellipse(65,46,24,6,'#DFD9CF');line('M 72 44 L 78 18 L 90 18',w=2.5)
            for x,y in [(53,64),(72,77),(61,96)]:flower(x,y,5,'#F1E6CF')
            return
        top=40 if i!=12 else 29; bottom=113
        path(f'M 39 {top} L 92 {top} L 85 {bottom} C 75 117 55 118 46 {bottom} Z',col)
        if i in [4,10]:
            path(f'M 35 {top} L 36 {top-8} L 94 {top-8} L 97 {top+1} Z','#D8C8B3')
            box(47,top+22,39,23,'#E8D8BC');line(f'M 55 {top+31} C 58 {top+23} 73 {top+24} 74 {top+32} C 71 {top+41} 58 {top+41} 55 {top+31}')
        elif i==12:
            box(40,23,51,11,'#D9CBB7');line('M 44 49 L 87 49',w=1)
            line('M 57 63 C 48 69 77 79 67 89 C 62 94 55 90 57 86','#EDE2CF',2)
        else:
            ellipse(65,top,26,6,'#E7DECF');ellipse(65,top,22,3,'#A88C70',None)
            if i==5:
                for x in [50,60,70,80]:line(f'M {x} 54 L {x-2} 105','#E5E1D1',1.7)
            else:line('M 45 63 C 64 69 77 68 88 62 M 46 74 C 64 81 77 79 88 73','#E6DDD0',2)
        return
    if i==8:
        # Double-wall glass.
        path('M 37 47 L 91 47 L 89 106 C 80 116 49 116 40 106 Z','#DDE3DE')
        path('M 43 52 L 85 52 L 82 96 C 73 103 57 104 47 96 Z','#B79475')
        ellipse(64,48,27,6,'#F0E9DB');ellipse(64,51,21,3,'#B79475',None);return
    if i==16:
        path('M 35 57 C 28 48 26 52 29 64 L 32 107 C 45 118 86 118 96 106 L 98 55 Z',col)
        ellipse(64,55,34,7,'#EEE4D2');line('M 43 65 L 46 105 M 83 66 L 81 106','#EFE3D0',1.7);return
    # Taller ceramic mugs. Distinct silhouettes, hand-painted patterns.
    left=32 if i not in [7,14] else 37; right=92; top=49 if i!=9 else 40
    handle(right,top+10)
    if i==7:
        path(f'M {left} {top} L {right} {top} L 86 109 C 75 117 52 116 44 108 Z',col)
    elif i==14:
        path('M 36 49 C 31 67 43 70 37 86 C 34 101 41 114 65 114 C 86 115 95 105 90 88 C 85 71 99 65 91 49 Z',col)
    else:
        path(f'M {left} {top} L {right} {top} L {right-3} 101 C 84 118 42 117 {left+3} 102 Z',col)
    ellipse((left+right)/2,top,(right-left)/2,7,'#EEE5D6')
    ellipse((left+right)/2,top+1,(right-left)/2-5,3.5,'#AE8A6A',None)
    if i==0:
        for x in [43,53,64,75,85]:line(f'M {x} 63 C {x-1} 78 {x+2} 94 {x} 104','#EBD9BE',2.3)
    elif i==1:
        for row in range(4):
            for column in range(5):
                if (row+column)%2==0:box(36+column*10,61+row*11,10,11,'#DFCFB7')
    elif i==6:
        for x,y in [(45,71),(68,70),(82,88),(55,94)]:flower(x,y,7,'#F1E5CD')
    elif i==7:
        for x in [49,62,76,86]:line(f'M {x} 61 L {x} 104','#E7DCC6',1)
        for y in [68,80,93]:line(f'M 44 {y} L 88 {y+1}','#E7DCC6',1)
    elif i==9:
        line('M 36 57 L 89 57 M 37 98 L 87 98','#EEE0C6',3)
        for x,y in [(45,69),(70,80),(54,92),(82,63)]:ellipse(x,y,1.7,1.8,'#F3E7CF',None)
    elif i==13:
        for x in [45,62,79]:
            line(f'M {x} 103 L {x+1} 69','#E8E1CB',1.2)
            for y in [77,89]:line(f'M {x} {y} C {x-12} {y-9} {x-8} {y-13} {x} {y-4} C {x+9} {y-13} {x+11} {y-8} {x} {y}','#E8E1CB',1.6)
    elif i==14:
        for x in [46,62,78]:line(f'M {x} 65 C {x-10} 77 {x+12} 88 {x} 104','#EEE0CB',2)
    elif i==19:
        flower(62,83,13,'#EDE0C8');flower(82,66,5,'#EDE0C8');flower(41,99,4,'#EDE0C8')
    steam(62,34)

def server(x=43,y=78):
    path(f'M {x} {y} L {x+32} {y} L {x+37} {y+32} C {x+32} {y+40} {x-4} {y+40} {x-6} {y+31} Z','#D7DDD4')
    ellipse(x+16,y+27,20,4,'#B79A77',None)
    line(f'M {x+34} {y+5} C {x+54} {y-2} {x+56} {y+28} {x+37} {y+26}',w=2)
    line(f'M {x+2} {y+10} L {x} {y+26}','#F1E9DB',2)
def dripper(x=34,y=45):
    ellipse(x+28,y,29,6,'#E5D7BD')
    path(f'M {x} {y} L {x+56} {y} L {x+39} {y+31} L {x+20} {y+31} Z','#B3BBA7')
    for dx in [11,23,35,47]:line(f'M {x+dx} {y+7} L {x+27+(dx-27)*.4} {y+26}','#F2E7D2',1)
    line(f'M {x+12} {y+33} L {x+46} {y+33}',w=2)
def kettle():
    path('M 42 67 C 35 74 30 92 31 106 C 47 119 78 116 87 105 C 86 83 78 71 74 67 Z','#A8B8B9')
    path('M 34 92 C 18 90 23 58 13 56 C 24 49 27 79 38 77','#A8B8B9')
    line('M 79 72 C 113 57 112 109 86 101',w=4)
    ellipse(58,67,19,4,'#E3D6BC');ellipse(58,61,5,3,'#C19B73')
    line('M 44 81 C 40 89 39 97 42 103','#E6E6D9',2)
def moka():
    path('M 44 76 L 80 76 L 89 111 L 34 111 Z','#B2B8B0')
    path('M 34 40 L 88 40 L 80 73 L 44 73 Z','#CBD0BE')
    path('M 34 40 L 29 39 L 38 56 Z','#CBD0BE')
    path('M 87 43 C 114 33 113 78 83 70 L 85 62 C 101 67 102 44 87 51 Z','#B28C73')
    line('M 43 39 L 62 30 L 82 39 M 61 29 L 61 25',w=2)
    for d in ['M 49 45 L 54 70','M 72 45 L 68 70','M 52 80 L 46 108','M 73 80 L 79 108']:line(d,'#8A8E82',1)
    box(44,73,36,6,'#C6AB86')
def grinder(electric=False):
    if electric:
        path('M 38 29 L 85 29 L 78 59 L 45 59 Z','#D4DCCF');ellipse(62,29,24,5,'#C2B393')
        path('M 44 59 L 82 59 L 85 102 L 33 102 L 34 88 L 45 88 Z','#9FAEAD')
        box(30,103,65,9,'#D3C6AF');box(56,80,20,27,'#E5DCCB');ellipse(65,70,4,4,'#B48E73')
    else:
        box(38,69,49,42,'#C3A17F');ellipse(62,69,25,6,'#DBC8AA');ellipse(62,111,24,4,'#C3A17F')
        path('M 47 46 L 78 46 L 72 67 L 52 67 Z','#ADB9AB');ellipse(62,46,16,5,'#E3D4BB')
        line('M 62 45 L 62 29 L 97 29',w=2.4);ellipse(99,29,7,4,'#AC8B70')
        box(48,85,28,18,'#E1C9A9');ellipse(63,93,2,2,'#9F7D62')
def equipment(i):
    col=PALETTE[i%5]
    if i==0:server();dripper();return
    if i==1:moka();return
    if i==2:
        box(25,42,83,64,'#A0B1B2');box(21,103,92,10,'#C3B092')
        path('M 24 43 L 28 30 L 104 30 L 109 43 Z','#D4D5C7')
        ellipse(47,56,8,8,'#EDE0C8');line('M 47 56 L 50 51',w=1)
        for x in [70,83,96]:ellipse(x,55,2,2,'#B99577')
        box(43,72,43,7,'#C8B492');line('M 62 80 L 62 84 M 73 80 L 73 84 M 88 74 L 100 89',w=2)
        path('M 50 88 L 78 88 L 75 101 L 53 101 Z','#E9D8BB');line('M 79 89 C 92 85 89 99 77 98')
        for x in range(32,106,8):line(f'M {x} 107 L {x+3} 110',w=.7)
        return
    if i in [3,4]:grinder(i==4);return
    if i==5:
        path('M 40 46 L 84 46 L 82 111 L 41 111 Z','#D4DDD2');box(37,42,52,7,'#B8B0A1')
        line('M 62 42 L 62 21 M 52 21 L 73 21',w=2)
        path('M 44 79 L 78 79 L 77 103 L 45 103 Z','#B39578',None)
        line('M 84 52 C 113 44 114 102 84 99',w=3)
        line('M 49 53 L 48 73','#F2E9D6',2);return
    if i==6:
        # Siphon, top globe and lower globe over burner.
        ellipse(58,38,20,20,'#D9E0D2');path('M 52 56 L 52 70 L 64 70 L 64 56','#D9E0D2')
        ellipse(58,84,23,21,'#E1DAC7');path('M 38 86 C 49 91 69 91 79 86 C 80 108 39 111 38 86 Z','#B79A79',None)
        line('M 87 38 L 87 112 M 75 112 L 101 112 M 80 70 L 87 65',w=3)
        ellipse(58,119,12,4,'#B6B7A6');line('M 58 116 L 58 110','#C29268',3);return
    if i==7:
        box(45,49,34,55,'#B4C0B5');box(40,104,45,7,'#D8C7A8');box(41,44,42,6,'#D8C7A8')
        line('M 62 44 L 62 24 M 48 24 L 77 24',w=3);line('M 53 58 L 52 95','#EEF0DF',2)
        for y in [66,80,93]:line(f'M 69 {y} L 77 {y}',w=.7)
        return
    if i==8:kettle();return
    if i==9:dripper(33,45);line('M 42 82 L 86 82',w=2);return
    if i==10:
        # Chemex hourglass and its leather tie.
        path('M 35 35 L 91 35 L 73 65 L 72 75 L 91 110 C 78 119 45 119 34 110 L 53 75 L 52 65 Z','#D7DDD1')
        path('M 49 84 L 77 84 L 88 108 C 73 114 48 115 37 109 Z','#B89875',None)
        path('M 51 65 L 75 65 L 73 78 L 52 78 Z','#BD9671');line('M 53 71 L 78 71 L 89 82 M 76 71 L 88 67',w=1.3)
        ellipse(63,35,28,5,'#EBE0CD');return
    if i==11:
        # Vietnamese phin on its glass: lid, perforated chamber and wide drip plate.
        path('M 42 81 L 83 81 L 80 111 C 72 118 52 118 45 110 Z','#D7DED1')
        path('M 46 96 L 80 96 L 77 108 C 69 114 54 114 47 107 Z','#B69A78',None)
        ellipse(63,80,34,5,'#C5B89C')
        path('M 42 46 L 84 46 L 80 77 L 46 77 Z','#B8C3B8')
        ellipse(63,46,25,5,'#DFD3BB');ellipse(63,40,5,3,'#B59A79')
        line('M 84 51 C 103 46 104 67 82 66',w=2)
        for x in [51,59,67,75]:
            for y in [58,67]:ellipse(x,y,.7,.7,INK,None)
        return
    if i==12:
        # Neapolitan flip pot: two stacked chambers with opposing handles.
        path('M 44 62 L 82 62 L 79 106 C 68 113 53 112 45 106 Z','#A4B3AF')
        path('M 43 33 L 82 33 L 83 61 L 44 61 Z','#D3D6C3')
        ellipse(63,33,20,4,'#E6D7BA');box(39,60,47,6,'#BEA98A')
        path('M 44 69 L 33 65 L 43 83 Z','#A4B3AF')
        line('M 84 76 C 109 65 109 100 83 96 M 42 42 C 22 36 23 57 42 55',w=3)
        line('M 50 76 L 51 100','#E7E2D0',1.5)
        return
    if i==13:
        box(29,90,78,23,'#A4B0AB');path('M 29 90 L 39 82 L 99 82 L 107 90 Z','#D7CBB4')
        box(70,96,24,9,'#DFDBC5');line('M 38 99 L 47 99',w=1)
        server(46,40);return
    if i==14:
        path('M 39 63 C 36 49 87 48 86 62 L 81 74 L 44 74 Z','#C5AD89')
        path('M 48 56 L 50 26 C 56 20 70 20 76 26 L 77 56 Z','#A3B3AF')
        ellipse(63,26,13,5,'#D4C6AC');ellipse(62,75,28,5,'#D6C8AD');return
    if i==15:
        ellipse(56,67,24,9,'#CFD5C4');path('M 32 67 L 36 82 C 45 94 69 94 79 82 L 80 67','#B5BFAE')
        path('M 79 71 L 117 59 L 121 67 L 80 81 Z','#BA9475');ellipse(56,68,16,4,'#A5896A',None)
        for x in [42,52,62,72]:ellipse(x,101,1,1,'#BDA081',None)
        return
    if i==16:
        # Cold drip tower.
        line('M 34 23 L 34 117 M 97 23 L 97 117 M 29 117 L 104 117',w=2)
        path('M 46 24 L 84 24 L 79 51 L 52 51 Z','#CDDAD5');ellipse(65,24,19,4,'#E4DCCA')
        line('M 65 53 L 65 59',w=1.5);box(48,63,34,19,'#B69A76');line('M 65 83 L 65 90',w=1)
        server(48,91);return
    if i==17:
        box(33,82,66,31,'#A2B1B4');box(33,49,31,34,'#C4B99E');box(33,42,66,10,'#DBD3BD')
        line('M 88 51 L 88 64 M 61 47 L 77 24 L 88 23',w=3)
        path('M 69 85 L 93 85 L 89 100 L 73 100 Z','#E4D6BA');line('M 94 87 C 108 83 103 98 92 96')
        ellipse(47,66,6,6,'#E5DDC8');line('M 47 66 L 50 62',w=1);return
    if i==18:
        path('M 42 47 L 85 47 L 84 101 C 75 114 49 115 42 101 Z','#C6D0C1')
        ellipse(63,47,22,6,'#DFD6BF');box(40,39,47,9,'#BFA98B');line('M 49 38 L 77 38',w=2)
        for x in [50,60,70,79]:line(f'M {x} 59 L {x} 98','#F1E8D3',1.4)
        line('M 86 57 C 112 48 112 92 85 93',w=3);return
    # Turkish cezve.
    path('M 47 65 L 76 65 C 78 82 90 98 87 108 C 73 118 45 118 34 108 C 36 89 45 81 47 65 Z','#C0987D')
    ellipse(61,65,15,4,'#E3C9A6');path('M 77 70 L 117 43 L 120 47 L 79 79 Z','#B5A887')
    line('M 45 94 C 54 101 73 102 80 95','#E9D5B8',1.2)

cups=['ribbed','checker','espresso','floralSaucer','takeaway','tumbler','daisy','grid','doubleGlass','enamel','travel','cappuccino','thermos','botanical','wavy','straw','beaker','teaBowl','sports','garden']
tools=['pourOver','moka','espressoMachine','handGrinder','electricGrinder','frenchPress','siphon','aeroPress','gooseneck','dripper','chemex','vietnamese','neapolitan','brewScale','tamper','portafilter','coldDrip','leverMachine','percolator','cezve']
for group,ids,draw in [('Together',cups,mug),('Explore',tools,equipment)]:
    for i,id in enumerate(ids):
        name=f'Caffe{group}_{id}'; folder=ROOT/'Brewwww/Assets.xcassets'/f'{name}.imageset';folder.mkdir(exist_ok=True)
        c=canvas.Canvas(str(folder/f'{name}.pdf'),pagesize=(140,140),pageCompression=1)
        c.translate(0,140);c.scale(1,-1);draw(i);c.showPage();c.save()
        (folder/'Contents.json').write_text(json.dumps({'images':[{'filename':f'{name}.pdf','idiom':'universal'}],'info':{'author':'xcode','version':1},'properties':{'preserves-vector-representation':True}},indent=2))
# Render a contact sheet from the actual asset PDFs using PyMuPDF.
import pymupdf as fitz
from PIL import Image, ImageDraw, ImageFont
sheet=Image.new('RGB',(1600,1190),'#F5F0E7');d=ImageDraw.Draw(sheet)
font=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',18)
small=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',12)
for group,ids,row in [('Together',cups,0),('Explore',tools,3)]:
    d.text((36,24+row*190),f'CAFFE {group.upper()}  /  '+('EVERY 5 CUPS' if row==0 else 'EVERY 3 INDEPENDENT CAFE CUPS'),fill=INK,font=font)
    for i,id in enumerate(ids):
        f=ROOT/'Brewwww/Assets.xcassets'/f'Caffe{group}_{id}.imageset'/f'Caffe{group}_{id}.pdf'
        doc=fitz.open(f);pix=doc[0].get_pixmap(matrix=fitz.Matrix(1.1,1.1),alpha=True)
        im=Image.frombytes('RGBA',[pix.width,pix.height],pix.samples)
        x=20+(i%10)*158;y=65+row*190+(i//10)*215
        sheet.paste(im,(x,y),im);d.text((x+8,y+157),f'{(i+1)*(5 if row==0 else 3):02}  {id}',font=small,fill=INK)
sheet.save(ROOT/'预览/咖啡手绘印章-40枚.png')
print('Generated 40 vector assets and contact sheet')
