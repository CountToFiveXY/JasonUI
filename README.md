# JasonUI

A native SwiftUI macOS frontend for the FastAPI services in the sibling
`JasonPython` repository.

## Install on a Mac

1. Download both repositories into the same parent folder:

   ```bash
   Your Folder/JasonUI
   Your Folder/JasonPython
   ```

2. In Finder, open `JasonUI` and double-click **Install JasonApp.command**.
3. Open JasonApp from Applications.
4. Click **Activate All Services**. The app installs missing Homebrew/Python
   packages, creates the virtual environment, and starts the backend.

Xcode is required to build the app. If Xcode, Homebrew, or another dependency
is unavailable, the installer or app displays a short tutorial with the exact
next steps. All in-app errors are selectable and copyable.

The app connects to `http://127.0.0.1:8000` by default. If that port is busy,
the startup workflow falls back to 8088 and then 8888 and updates the app
automatically. You can also change the URL in the Server screen or macOS
Settings (`⌘,`).

The app supports server health, URL shortening, ranking-card generation,
Temporal hello/greeting workflows, and the image endpoint.

## Package as a macOS app

### One-click install or update

Double-click **`Install JasonApp.command`** in Finder to install or replace the
copy in Applications. The legacy **`Update JasonUI.command`** runs the same
installer. It automatically:

1. Runs the test suite.
2. Creates a fresh release build and app bundle.
3. Quits the currently running JasonUI app.
4. Replaces `/Applications/JasonApp.app`.
5. Reveals the installed app in Finder.

If macOS asks which application should open the file, choose Terminal. If
macOS blocks the first launch, right-click the file and choose **Open**.

### Manual packaging

```bash
./scripts/package_app.sh
```

This creates `.build/app-package/JasonApp.app`. Copy it to `/Applications` for
normal Finder, Spotlight, and Dock access.
