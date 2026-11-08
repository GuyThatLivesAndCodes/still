# still.

*Some things are better left in the moment.*

A private journaling app: write it, seal it for 14 days, and let it go.

## Build

GitHub Actions builds an **unsigned** `.ipa` on every push to `main`
(Actions tab → latest run → **Still-ipa** artifact). The Xcode project is
generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Install with Sideloadly

1. Download and unzip the `Still-ipa` artifact to get `Still.ipa`.
2. Open Sideloadly, plug in your iPhone, drag in `Still.ipa`.
3. Enter your Apple ID and press Start. Sideloadly signs and installs it.
4. On the iPhone: Settings → General → VPN & Device Management → trust your Apple ID.
5. iOS 16+: enable Developer Mode (Settings → Privacy & Security).

Free Apple IDs expire sideloaded apps after 7 days; re-sideload to refresh.
Your entries stay on the device between reinstalls as long as the bundle ID
(`com.guythatlives.still`) stays the same.

## Local development (macOS)

```sh
brew install xcodegen
xcodegen generate
open Still.xcodeproj
```
