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

1. Install **Xcode** from the Mac App Store and open it once.
2. Configure Xcode in Terminal:

   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -license accept
   ```

3. Install [Homebrew](https://brew.sh/) if it is not already installed.
4. Install the backend tools:

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

1. Open **JasonApp** from Applications.
2. Select **Server**.
3. Click **Activate All Services**.

The app starts Redis, Temporal, the Temporal worker, and JasonPython. Use
**Check Connection** to refresh their status and **Close Server** to stop them.

The backend normally uses `http://127.0.0.1:8000`. If that port is occupied,
it tries ports `8088` and `8888` automatically.

## Update JasonApp

JasonApp checks the remote JasonUI `main` branch when it opens and every 15
minutes afterward. The version control at the bottom-left changes to an
**Update** button when another machine has pushed a newer commit.

Click **Update** to automatically:

1. Confirm the local JasonUI repository has no uncommitted changes.
2. Fast-forward the local repository from `origin/main`.
3. Run the Swift tests.
4. Rebuild and verify JasonApp.
5. Replace `/Applications/JasonApp.app` and restart it.

If the local repository contains uncommitted work, the update stops without
changing it. Commit or discard those changes, then click **Update** again.

You can also double-click `Install JasonApp.command` at any time to rebuild and
replace the app manually.

## Troubleshooting

- App installation errors remain visible in the installer Terminal window.
- Service startup logs are stored at `~/Library/Logs/JasonApp/services.log`.
- Keep `JasonUI` and `JasonPython` in the same parent folder.
