# JasonUI

A native SwiftUI macOS frontend for the FastAPI services in the sibling
`JasonPython` repository.

## Run

1. Start Redis, Temporal, its worker, and FastAPI from `JasonPython`.
2. Run JasonUI from Terminal:

   ```bash
   cd /Users/sword23/Workspace/JasonUI
   swift run JasonUI
   ```

3. The app connects to `http://127.0.0.1:8080` by default. Change it in the
   Server screen or macOS Settings (`⌘,`).

The app supports server health, URL shortening, ranking-card generation,
Temporal hello/greeting workflows, and the image endpoint.

## Package as a macOS app

### One-click local update

Double-click **`Update JasonUI.command`** in Finder whenever you want to release
your latest code changes to the copy in Applications. It automatically:

1. Runs the test suite.
2. Creates a fresh release build and app bundle.
3. Quits the currently running JasonUI app.
4. Replaces `/Applications/JasonUI.app`.
5. Opens the updated app.

If macOS asks which application should open the file, choose Terminal. If
macOS blocks the first launch, right-click the file and choose **Open**.

### Manual packaging

```bash
./scripts/package_app.sh
```

This creates `.build/app-package/JasonUI.app`. Copy it to `/Applications` for
normal Finder, Spotlight, and Dock access.
