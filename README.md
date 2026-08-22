# JasonUI

A native SwiftUI macOS frontend for the FastAPI services in the sibling
`JasonPython` repository.

## Run

1. Start Redis, Temporal, its worker, and FastAPI from `JasonPython`.
2. Open `Package.swift` in Xcode and run the `JasonUI` scheme.
3. The app connects to `http://127.0.0.1:8080` by default. Change it in the
   Server screen or macOS Settings (`⌘,`).

The app supports server health, URL shortening, ranking-card generation,
Temporal hello/greeting workflows, and the image endpoint.

## Package as a macOS app

```bash
./scripts/package_app.sh
```

This creates `.build/app-package/JasonUI.app`. Copy it to `/Applications` for
normal Finder, Spotlight, and Dock access.
