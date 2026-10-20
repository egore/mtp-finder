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
| `Scripts/` | Library embedding |

## Requirements

- macOS 13+, Xcode
- Apple Development signing identity (team set in `project.yml`)
- `brew install libmtp xcodegen`

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
- Opening Android File Transfer.app at the same time conflicts.

## Change identity

The team ID `4FMS9MCK4C` and bundle prefix `com.cbrill.mtpfinder` appear
in `project.yml`, `Sources/MTPShared/MTPProtocol.swift` and
`Resources/com.cbrill.mtpfinder.helper.plist`. Change all three. The app
group and Mach service name derive from them.

## Limitations

- Existing files can't be overwritten in place (no partial writes in
  MTP, and replacing would change the item ID).
- No moving between folders.
- Phone-side changes appear only after reopening a folder.
- Downloads and uploads are staged in the app group container.
- Debug, Apple Development signed. Distribution needs Developer ID,
  hardened runtime, notarization, and signed embedded dylibs.
