# Credits

BarNook is distributed under the Apache License 2.0. See [LICENSE](LICENSE).

## Origin and modifications

BarNook is based on [ronny/ellipsis](https://github.com/ronny/ellipsis)
by Ronny Haryanto. The original Apache 2.0 license and copyright notice
remain in [LICENSE](LICENSE). Chaehyeon Lee modified the floating bar to pin
menu bar items and changed the pin fit and rehide behavior in 2026. Modified
upstream files carry individual change notices.

## Ships inside the application

The app bundles [Sparkle 2](https://sparkle-project.org) for updates. Its
license and included third-party notices are in the bundle as `Sparkle-LICENSE`.
The `AppIcon` asset is a bar over a sheltered item on a gradient, drawn by
`scripts/make-icon-art.swift`. The matching menu bar nook icon is hand-drawn.
The other menu bar icon choices are the SF Symbols `ellipsis`, `chevron.left`,
`chevron.right`, `circle.fill` and `star.fill`, used under the Apple SDK licence.

## Website

The website in `site/` uses [Pretendard](https://github.com/orioncactus/pretendard)
1.3.9 by Kil Hyung-jin, shipped unmodified as `PretendardVariable.woff2` under
the SIL Open Font License 1.1 with Reserved Font Name. The license is in
`site/assets/fonts/LICENSE.txt`. The site is not part of the application.

## Apple frameworks

AppKit, SwiftUI, Observation and ServiceManagement are used under the Apple SDK
licence that comes with Xcode. `MenuBarClientCore` is a private Apple framework
that BarNook loads at run time with `dlopen`. Nothing from it is redistributed.
