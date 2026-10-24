# MTP Finder

Shows Android (MTP) devices in Finder's sidebar via a File Provider
extension and allows browsing, copying, renaming and deleting files.

```
Finder ─> FileProviderExt.appex (sandboxed)
              │ XPC
          MTPHelper (LaunchAgent, unsandboxed)
              │ MTPKit ─> libmtp ─> libusb
```

The helper owns the USB device. macOS's `ptpcamerad` claims MTP
devices and is killed before each open. The sandboxed extension can't
do that, hence the split.

| Path | Purpose |
|---|---|
| `Sources/MTPShared` | Types, XPC protocol, `MTPClient` |
| `Sources/MTPKit` | libmtp wrapper (`MTPSession`) |
| `Sources/mtpls` | CLI: list devices, `selftest` round trip |
| `Helper/` | `MTPHelper` launch agent, USB hotplug watcher |
| `Extension/` | File Provider extension |
| `App/` | Menu-bar app, registers helper and domains |
| `Scripts/` | Library embedding, icon generator (`swift Scripts/make-icon.swift`) |

## Requirements

- macOS 13+, Xcode
- An Apple Development signing identity (Xcode > Settings > Accounts)
- `brew install libmtp xcodegen`

## Prepare

The Apple team ID is not stored in the repo. Create the git-ignored
`Config/Local.xcconfig` with yours:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

and replace `XXXXXXXXXX` with your team ID. To look it up, run

```sh
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
```

and take the `OU=` value (not the ID in parentheses after the name).
The build fails with a message if the team is missing.

## Build

```sh
xcodegen generate
xcodebuild -project AndroidFileTransfer.xcodeproj -scheme MTPFinder \
  -configuration Debug -allowProvisioningUpdates -derivedDataPath build build
```

A post-build script copies `libmtp` and `libusb` from Homebrew into the
app and re-signs the helper. Set `BREW_PREFIX` if Homebrew is not in
`/opt/homebrew`.

CLI only (no Xcode):

```sh
swift build
.build/debug/mtpls             # list
.build/debug/mtpls selftest    # upload, rename, download, delete
```

## Deploy

```sh
pkill -x MTPFinder
rm -rf ~/Applications/MTPFinder.app
cp -R build/Build/Products/Debug/MTPFinder.app ~/Applications/
open ~/Applications/MTPFinder.app
pluginkit -e use -i com.cbrill.mtpfinder.provider
```

Run the app from a stable location, not the build directory.

First launch:

1. Approve the helper if prompted (System Settings > General >
   Login Items & Extensions).
2. Run the `pluginkit` command above. Without it File Provider fails
   with error -2011 ("sync not enabled").
3. Unlock the phone and set USB mode to **File transfer**.
4. The device appears in Finder under Locations and in
   `~/Library/CloudStorage/MTPFinder-<name>`. Allow the file access
   prompt on first use.

## Operate

- Menu-bar icon: device list, Refresh, Reset (re-adds all domains).
- Reset from a shell, if the icon is hidden:
  `open ~/Applications/MTPFinder.app --args --reset`.
  Required after changing item metadata, as macOS caches it.
- A locked phone yields an empty or failing folder. Unlock and reopen.
- Opening Android File Transfer.app at the same time conflicts (see FAQ).

## FAQ

**The device is listed but its folder is empty or fails with "Device
locked or not in File transfer mode".**
Check the phone first: unlocked, USB mode **File transfer**, the access
prompt allowed. If that is fine, another program probably has the phone.
MTP allows one session at a time. A program that quits uncleanly (a
crash, `kill`) leaves its session open and the phone refuses the next
one. The helper drops and reopens its session once on this error, so
retry after a few seconds. If it persists, quit the other program, run
`pkill -x MTPHelper` (launchd restarts it) and replug the cable.

**Which programs conflict?**
Android File Transfer (the menu-bar icon shows a warning while it runs),
other MTP tools such as `mtpls`, and anything else using libmtp or
libusb on the same phone. `mtpls` refuses to run while `MTPHelper` is
alive unless you pass `--force`. The helper keeps its session open once
a request has used it, so quit MTPFinder and run `pkill -x MTPHelper`
first. launchd restarts the helper without a session, then `--force`
is safe.

**How do I see what the helper is doing?**
`log stream --predicate 'subsystem == "com.cbrill.mtpfinder"'` shows
when it drops a stale session.

## Icons

- App icon: `App/Assets.xcassets`, rendered by `Scripts/make-icon.swift`.
- Finder sidebar icon: SF Symbol `iphone.gen3`, set through
  `CFBundleSymbolName` in the extension's Info.plist (`project.yml`).
  Finder accepts only SF Symbol names there. Run the `--reset` command
  below to refresh a cached icon.

## Change identity

The team ID comes from `Config/Local.xcconfig` (see Prepare). Entitlements
use `$(TeamIdentifierPrefix)`, `Scripts/embed-libs.sh` fills it into the
helper's launch plist, and the code reads it from its own signature.

The bundle prefix `com.cbrill.mtpfinder` appears in `project.yml`,
`Sources/MTPShared/MTPProtocol.swift` and
`Resources/com.cbrill.mtpfinder.helper.plist`. Change all three. The app
group and Mach service name derive from it.

## Limitations

- Existing files can't be overwritten in place (no partial writes in
  MTP, and replacing would change the item ID).
- No moving between folders.
- Phone-side changes appear only after reopening a folder.
- Downloads and uploads are staged in the app group container.
- Debug, Apple Development signed. Distribution needs Developer ID,
  hardened runtime, notarization, and signed embedded dylibs.
