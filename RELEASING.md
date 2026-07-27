# Cutting a new release (maintainer notes, not for end users)

Steps to ship a new version of UsageBar. Run all commands from this folder (`output/opensource-prep/`).

## 1. Bump the version (optional, but recommended for anything past a trivial fix)

Edit `project.yml`, add/update under the `TokenUsageWidget` target's `info.properties`:

```yaml
CFBundleShortVersionString: "0.2.0"
```

## 2. Build and test

```bash
xcodegen generate
xcodebuild -project TokenUsageWidget.xcodeproj -scheme TokenUsageWidget build
xcodebuild -project TokenUsageWidget.xcodeproj -scheme TokenUsageWidgetTests test
```

Both must succeed before continuing.

## 3. Build the Release configuration

```bash
xcodebuild -project TokenUsageWidget.xcodeproj -scheme TokenUsageWidget -configuration Release clean build
```

The built `.app` lands somewhere under `~/Library/Developer/Xcode/DerivedData/TokenUsageWidget-*/Build/Products/Release/TokenUsageWidget.app` — the exact hash in the folder name changes per machine/checkout, find it with:

```bash
find ~/Library/Developer/Xcode/DerivedData -path "*/Build/Products/Release/TokenUsageWidget.app" -maxdepth 5
```

## 4. Zip it

```bash
APP_PATH="<path found in step 3>"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" UsageBar-vX.Y.Z.zip
```

(`ditto` preserves the `.app` bundle structure correctly — don't use Finder's "Compress" or plain `zip`, they can mangle bundle metadata.)

## 5. Tag and publish

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
gh release create vX.Y.Z UsageBar-vX.Y.Z.zip --title "UsageBar vX.Y.Z" --notes "<what changed>"
```

To replace the file on an existing release instead of creating a new one:

```bash
gh release upload vX.Y.Z UsageBar-vX.Y.Z.zip --clobber
```

## 6. Update your own local copy (optional)

```bash
killall UsageBar 2>/dev/null
rm -rf "/Applications/UsageBar.app"
cp -R "$APP_PATH" "/Applications/UsageBar.app"
open "/Applications/UsageBar.app"
```

## Notes

- `gh` (GitHub CLI) must be installed and authenticated (`gh auth status` to check). If not: `brew install gh` then `gh auth login`.
- The app isn't signed with a paid Apple Developer certificate, so anyone downloading it (including you, testing a fresh copy) needs to right-click → Open the first time instead of double-clicking, or Gatekeeper blocks it.
