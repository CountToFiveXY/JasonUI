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

1. Select **Server**.
2. Click **Activate All Services**.

The app starts Redis, Temporal, the Temporal worker, and JasonPython. Use
**Check Connection** to refresh their status and **Close Server** to stop them.

The backend normally uses `http://127.0.0.1:8000`. If that port is occupied,
it tries ports `8088` and `8888` automatically.

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
- Service startup logs are stored at `~/Library/Logs/JasonApp/services.log`.
- Keep `JasonUI` and `JasonPython` in the same parent folder.
