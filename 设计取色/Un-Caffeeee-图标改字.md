# Un Caffèee! 名称与图标

2026-10-28：按要求删去末尾一个普通 e，当前名称为 **Un Caffèee!**（è 后两个普通 e）。桌面显示名称、设置页、个人信息品牌文字、护照机读文字、开屏无障碍名称均已同步。

App 图标与开屏 `LaunchBrand` 使用同一份新 logo，保留纸纹、金色轮廓和白色手写风格。使用 imagegen 编辑上一版图标，生成原图留档于 [Un-Caffeee-改字原图.png](品牌素材/Un-Caffeee-改字原图.png)，经 sips 规范为 1024×1024、无 alpha 的 PNG。两份应用资源 SHA-256 均为 `022f512d5bccfc5461b33e78a82029a164a4906077bc0e5f85f01de5d8581d7d`。

以下保留上一版改字记录。

---

# Un Caffèeee! 名称与图标

按最终要求保留原 Logo 的纸纹、赭金轮廓与白色手写风格，将原来的文字替换为 `Un Caffèeee!`，排为 `Un` / `Caffèeee!` 两行。使用内置 imagegen 的图片编辑模式，原 AppIcon 为编辑目标；未采用最初生成的另一套咖啡杯设计。

本次是生成式改字，保留了原 Logo 的视觉风格，不宣称字区以外像素完全不变。生成原图为 1254×1254、无透明通道；用系统 sips 规范到应用图标所需的 1024×1024。

- 最终应用图标：[AppIcon.png](../Brewwww/Assets.xcassets/AppIcon.appiconset/AppIcon.png)
- 生成改字原图：[Un-Caffeeee-改字原图.png](品牌素材/Un-Caffeeee-改字原图.png)
- 改字前参考留档：[Original-Brewwww-AppIcon.png](品牌素材/Original-Brewwww-AppIcon.png)

App 的显示名称 CFBundleDisplayName、设置页版本行与个人信息上的品牌文字均改为 `Un Caffèeee!`。包标识、签名团队与记录存储目录保持原值，更新安装可继续使用已有记录。

最终提示词（内置 imagegen；opaque；编辑参考为原 AppIcon）：

```text
Edit target: the provided original 1024x1024 app icon.
Use case: text-localization.
Change ONLY the white hand-lettered text inside the existing caramel-gold abstract coffee-cup shaped emblem. Replace ALL of the original "Brew www!" lettering with the exact new brand name "Un Caffèeee!".
Preserve the original cream textured paper background, identical caramel-gold color, identical emblem silhouette and placement, original canvas, flat ink style and overall proportions. Do not redesign the logo, add a cup illustration, saucer, steam, outlines, shadows or any decorative motifs.
Typography: imitate the ORIGINAL irregular friendly WHITE hand-painted lettering (not cursive script or a new font aesthetic). Arrange naturally into two centered lines inside the existing gold silhouette: first line "Un", second line "Caffèeee!". Keep the full second word on a single line, sizing the letters to fit comfortably within the silhouette with margins. The new name must be spelled EXACTLY U n [space] C a f f è e e e !. The è is one lowercase e with a GRAVE accent; there are THREE plain e letters after it. Preserve the exclamation mark as part of the second line. No old letters may remain.
All pixels outside the text area should remain visually identical to the reference. Square fully opaque app icon, no rounded outer mask or transparent corners. Deliver the finished edited icon only.
```

验证：1024×1024 PNG、无 alpha 通道；设备 SDK 编译通过，产物 CFBundleDisplayName 为 `Un Caffèeee!`。Xcode 的内部产品名称、CFBundleName 与源文件目录仍沿用原工程名称，不影响桌面显示名称或更新安装。图标 SHA-256：`40df9f2835a1d741cd1dd998166eb2ec311ea7e5a2e7eddbceb999482918dd91`。
