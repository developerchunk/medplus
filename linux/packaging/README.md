# MedBillings on Linux (shop PC)

The installer is a single file, `medbillings_<version>_amd64.deb`. On Linux Mint
you double-click it, click **Install** and type the password. It:

- puts MedBillings in the Start menu (Office) and an icon on the desktop
- opens MedBillings automatically after login
- installs what MedBillings needs (zenity for the Save/Open dialogs, etc.)
- keeps only one copy of the app open (clicking the icon again brings the
  open window to the front)

Shop data lives in `~/Documents/MedBillings` (database, bills, backups).
Installing, upgrading or removing the app **never touches it**.

## 1. Make the installer

Flutter can't build a Linux app on a Mac, so build it on one of these:

**A. GitHub (no Linux PC needed)**: push the project to a GitHub repo, open
**Actions → Linux installer → Run workflow**, wait about 10 minutes and
download `medbillings-linux-deb` from the run's **Artifacts** section (a zip
with the `.deb` inside). Pushing a tag such as `v1.0.1` also builds it.

**B. Any 64-bit Linux PC** (Ubuntu 22.04+/Mint 21+, Flutter installed, internet on):

```bash
linux/packaging/build_deb.sh --install-deps
```

The installer lands in `dist/`. Build on the oldest Ubuntu/Mint you need to
support: one built on 22.04 runs on Mint 21 and 22.

Options: `--no-autostart` (don't open at login) and `--skip-build` (repackage
the last build). The version comes from `version:` in `pubspec.yaml`, so bump it
before each release; installing a newer `.deb` upgrades in place.

## 2. Set up the shop PC (one time)

1. Install **Linux Mint Xfce Edition** (64-bit). During setup, tick
   **Log in automatically** and pick English (India) or Marathi.
2. Connect to the internet, open **Update Manager** and install all updates.
3. Copy the `.deb` from a pen drive, double-click it → **Install**.
4. Restart. MedBillings should open by itself.
5. Printer: **Start menu → Printers → Add**, and print a test page. Then in
   MedBillings **Settings** choose that printer and the paper size.
6. **Start menu → Timeshift**: set up daily snapshots so a bad update can be
   undone.

If the desktop icon shows "Untrusted application launcher", click
**Mark executable** / **Launch anyway** once. It won't ask again.

## Updating or removing

- **Update**: double-click the newer `.deb` → Install. Data stays.
- **Remove**: `sudo apt remove medbillings`. Data in Documents/MedBillings stays.
- **Turn off auto-open**: Start menu → Session and Startup → Application
  Autostart → untick MedBillings.

## Backups

Every week, in MedBillings go to **Settings → Data & backup → Export full
backup…** and save the backup to a pen drive. If the HDD fails,
that pen drive is the only copy of the shop's bills and stock.
