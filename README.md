# Brewwww!

Brewwww! is a native SwiftUI app for keeping a visual journal of drinks and cafe visits. It supports iOS 17 and later. The Xcode project can be regenerated from `project.yml` with XcodeGen.

## Features

- Browse entries in monthly and weekly calendar views, with monthly drink and cafe counts.
- Add, edit, and delete entries using a new photo or one from the photo library. Entries can include a date, cafe, city, drink name, rating, and notes.
- Explore drink lists, photo cards, a stamp collection, and a map of visited cafes and cities.
- Keep entries and photos on the device so they remain available after restarting the app.
- Customize profile details, preferences, cafes, stamps, and passport appearance.
- Use Apple Vision to cut out the main subject of a photo, switch back to the original image, and save a sticker.
- Adapt the interface to different window sizes and display configurations, including expanded and hinged layouts.

## Run the app

1. Open `Brewwww.xcodeproj` in Xcode.
2. Select the `Brewwww` scheme and an iPhone simulator, then run the app.
3. To install it on an iPhone, enable Developer Mode on the device and select your Apple development team in Xcode's **Signing & Capabilities** settings. Use a unique bundle identifier if needed.

To regenerate the project and build from the command line:

```sh
xcodegen generate
xcodebuild \
  -project Brewwww.xcodeproj \
  -scheme Brewwww \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Current status

Entries are stored locally; iCloud sync is not configured. The repository does not include sample personal data, so a fresh installation starts with an empty journal. Photo cutout uses Apple Vision, but its performance on a physical iPhone has not yet been measured. The project does not set a `DEVELOPMENT_TEAM`; device builds need local signing configuration.
