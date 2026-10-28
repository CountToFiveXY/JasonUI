# JasonApp

A native macOS frontend for the APIs in JasonPython.

## First-time setup

### Step 1: Download both repositories

Open Terminal and clone both repositories into the same folder:

```bash
mkdir -p ~/Workspace
cd ~/Workspace
git clone git@github.com:CountToFiveXY/JasonUI.git
git clone git@github.com:CountToFiveXY/JasonPython.git
```

GitHub links:

- Frontend: [CountToFiveXY/JasonUI](https://github.com/CountToFiveXY/JasonUI)
- Backend: [CountToFiveXY/JasonPython](https://github.com/CountToFiveXY/JasonPython)

These commands use SSH. Your GitHub account must have an SSH key configured.
You can verify access before cloning:

```bash
ssh -T git@github.com
```

Keep the folders next to each other:

```text
Workspace/
├── JasonUI/
└── JasonPython/
```

### Step 2: Install dependencies

1. Install the **Command Line Tools**, which carry the Swift toolchain JasonApp
   builds with. Full Xcode is not required.

   ```bash
   xcode-select --install
   ```

   If Xcode is already installed and `swift --version` fails, accept its
   licence (`sudo xcodebuild -license accept`) or switch to the Command Line
   Tools (`sudo xcode-select -s /Library/Developer/CommandLineTools`).

2. Install [Homebrew](https://brew.sh/) if it is not already installed.
   Check first:

   ```bash
   brew --version
   ```

   If that reports `command not found`, run the official installer. It asks
   for your Mac password and may install the Command Line Tools:

   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

   On Apple silicon Macs, Homebrew installs to `/opt/homebrew`, which is not
   on your `PATH` yet. Add it for future Terminal windows and this one:

   ```bash
   echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
   eval "$(/opt/homebrew/bin/brew shellenv)"
   ```

   The installer prints the same commands under **Next steps**; follow those
   if they differ.

3. Install the backend tools:

   ```bash
   brew install redis temporal python
   ```

JasonApp creates the Python virtual environment and installs Python packages
automatically when the backend starts.

### Step 3: Install JasonApp on your Mac

Open the `JasonUI` folder in Finder, then double-click:

```text
Install JasonApp.command
```

The installer tests and builds the project, then installs JasonApp at:

```text
/Applications/JasonApp.app
```

If macOS blocks the command, right-click it and select **Open**.

### Step 4: Start the services

The installer opens JasonApp for you when it finishes. To start it later, open
**JasonApp** from Applications.

Opening JasonApp starts the **core services** when they are not running:
Redis and the JasonPython backend, which reads Firestore. File Transfer,
Leaderboard, Gauntlet and the URL shortener work from that alone. Temporal
and Kafka stay off; the features that need them (Workflows, Kafka messages)
report that the service is not running.

The middle button on the **Server** pane follows what is running:

- **Activate All Services** while anything is down: starts Redis, Kafka,
  Temporal, their workers, and the backend.
- **Restart Services** once everything is up: stops them all and starts them
  again, which loads the backend checkout's current code.

Use **Check Connection** to refresh their status and **Close Server** to stop
them.

The backend normally uses `http://127.0.0.1:8000`. If that port is occupied,
it tries ports `8088` and `8888` automatically.

## Run your local changes

Use this loop to try changes in either repository before pushing them.

| Changed | Run | What it does |
|---|---|---|
| JasonUI | `./scripts/run_local.sh` (in `JasonUI`) | Builds the app from this checkout, uncommitted changes included, quits any running JasonApp, and opens the new build. |
| JasonPython | **Activate All Services** or **Restart Services** on the Server pane | Stops the backend and starts `JasonPython/scripts/run_local.sh` again, so the backend runs the checkout's current code. |
| Both | Both, UI first | The backend keeps running while the app restarts, so restart it from the new app. |

```bash
cd ~/Workspace/JasonUI
./scripts/run_local.sh
```

The script checks SwiftUI and Observation support with the selected Apple
toolchain. It tries the default macOS SDK first, then other SDKs installed in
the same developer directory if necessary. This also applies when packaging
the app directly. macOS 14 or newer and Swift 6 or newer are required.
It does not change the system's Xcode selection or install developer tools.

To choose a specific SDK, use:

```bash
JASONUI_SWIFT_SDK="/path/to/MacOSX.sdk" ./scripts/run_local.sh
```

To use another installed Xcode, set `DEVELOPER_DIR` to that Xcode's
`Contents/Developer` directory when running the script. If no compatible SDK
is installed, the script reports the problem before closing the running app.

The local build runs from `.build/app-package/JasonApp.app`, and
`/Applications/JasonApp.app` is left as it was. The backend does not reload
on its own when its code changes; restart it after each backend change. The
app finds the backend checkout next to JasonUI, or at `JASONPYTHON_PATH`.

## Update JasonApp

Every commit pushed to `main` is built and published by GitHub Actions
(`.github/workflows/release.yml`), which runs the tests, packages
`JasonApp.app`, and attaches it to a release as `JasonApp.zip`.

JasonApp checks the remote JasonUI `main` branch when it opens and every 15
minutes afterward. The version control at the bottom-left changes to an
**Update** button when another machine has pushed a newer commit.

Click **Update** to automatically:

1. Download the published `JasonApp.zip` and unpack it.
2. Verify its signature.
3. Replace `/Applications/JasonApp.app` and restart it.

Because the app is downloaded rather than compiled, **a Mac that only runs
JasonApp needs neither a Swift toolchain nor a copy of this repository** to
stay up to date.

If no build has been published yet — CI still running, or working offline —
the update falls back to compiling from a local checkout, which is the older
behaviour: confirm the repository is clean, fast-forward `origin/main`, run
the tests, rebuild, and install. That fallback needs the Command Line Tools
and a clean worktree; without a checkout the update reports why it could not
download instead.

### Setting up another Mac

To run JasonApp on a second Mac without a Swift toolchain, download
`JasonApp.zip` from the [latest release](https://github.com/CountToFiveXY/JasonUI/releases/latest),
unzip it into `/Applications`, and open it. The Update button maintains it from
then on.

That Mac still needs the JasonPython repository and Homebrew to run the backend
locally — **the Update button does not update the backend.** Alternatively,
point it at a backend running on another machine by changing the Server URL on
the Server pane.

You can also double-click `Install JasonApp.command` at any time to rebuild and
replace the app manually.

## Troubleshooting

- App installation errors remain visible in the installer Terminal window.
- Frontend logs are stored at `~/Documents/JasonApp/frontend.log`.
- Backend and service startup logs are stored at `~/Documents/JasonApp/backend.log`.
- Keep `JasonUI` and `JasonPython` in the same parent folder.


### Expense Ledger

Ledger uses the configured JasonPython server for loading, adding, renaming, and
removing expenses. Start/restart the backend with the matching Ledger API changes,
then open Ledger or click Refresh. Bill images are still generated locally.

Firestore is authoritative. The UI waits for successful saves and shows errors
without discarding the input. Clear All deletes only the displayed records and
reports partial failures. Refresh fetches changes made on other devices; there
is no background or offline editing sync in this version.

The previous `ledger.expenses` UserDefaults data is left intact as a local backup;
it is not automatically uploaded or mixed into the remote list.
