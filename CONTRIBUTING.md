# Contributing to Nimbus

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Set up

You need macOS 14 or later and the Xcode command line tools.

```sh
git clone https://github.com/harshavardanan/Nimbus.git
cd Nimbus
./scripts/run.sh        # build, bundle, sign and launch
```

### Tests

The tests use Swift Testing, which ships with Xcode 16 and later:

```sh
swift test
```

If you only have the command line tools, Swift Testing lives in a folder SwiftPM doesn't search, so pass it in:

```sh
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
swift test --enable-swift-testing -Xswiftc -F$FW -Xlinker -F$FW \
  -Xlinker -rpath -Xlinker $FW -Xlinker -rpath -Xlinker $LIB
```

## Adding a widget

A widget is one class that conforms to `IslandWidget` (see `Sources/Nimbus/Widgets/IslandWidget.swift`)
plus one line in `WidgetRegistry`. Its on/off switch in Settings and its icon beside the notch appear on
their own.

```swift
import Combine
import SwiftUI

@MainActor
final class HelloWidget: IslandWidget {
    let id = "hello"
    let title = "Hello"
    let subtitle = "Says hello"
    let symbol = "hand.wave.fill"          // an SF Symbol, used for the icon beside the notch
    let defaultEnabled = true
    var requestPeek: ((Double) -> Void)?   // call it to pop the island open for a few seconds

    var compactPriority: Int? { nil }      // return a number to claim the compact island while live
    var changes: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }

    func expandedView(topInset: CGFloat) -> AnyView {
        AnyView(WidgetFrame(headline: "Hello", topInset: topInset) {
            Text("Hello from the notch")
        })
    }

    func expandedSize(settings: IslandSettings, closed: CGSize) -> CGSize {
        CGSize(width: settings.expandedWidth, height: min(settings.expandedHeight, 138))
    }
}
```

Then add `HelloWidget()` to the list in `WidgetRegistry.init`.

Guidelines:

- **Start and stop cleanly.** Do polling and watching in `start()` and undo it in `stop()`. A widget the user
  switches off must use no CPU.
- **Don't poll fast.** Prefer events (notifications, file watching) over timers. Nimbus sits on screen all day.
- **Use `WidgetFrame`, `.reveal(n)` and the `islandTheme` environment** so your widget follows the user's
  colours and animations.
- **Parsing goes in pure functions** so it can be unit tested. See the tests for battery files and commands.
- **Be honest about privacy.** If a widget reads personal data or uses the network, say so in the README.

## Themes

A theme is a set of values in `ThemePreset` (`Settings/IslandSettings.swift`). Users can also export and share
their whole look from Settings → Presets as JSON.

## Code style

Match the code around you: names, comment density and idiom. Keep comments for the why, not the what.
Keep the build free of warnings.

## Pull requests

- Say what changed and why, and how you tried it.
- Include screenshots for visual changes.
- Add or update tests for parsing and logic.
- Keep one change per pull request where you can.
