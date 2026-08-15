# NativeCode

NativeCode is a native iOS workspace inspired by the workflow of Visual Studio Code. It is built with Swift and SwiftUI only. The product does not use a web view, HTML, CSS or a web application shell.

## Direction

- Native `NavigationStack`, `List`, `Form`, toolbars, sheets and iOS file importer.
- A ChatGPT-inspired project navigator drawer with the selected project's tree, GitHub access and workspace destinations.
- Local folder projects with real file reading and saving through the iOS document picker.
- GitHub repository loading through the REST API: files, branches, commits and Actions runs.
- A focused editor with monospace layout, line numbers and lightweight syntax highlighting.
- Keychain-backed GitHub token storage, haptics and reduced-motion settings.
- Liquid Glass only where it belongs: system surfaces and the project navigator, not decorative dashboard cards.

## GitHub token

Create a fine-grained token for the repositories you want to use:

- Metadata: read-only
- Contents: read and write
- Actions: read and write

NativeCode stores the token in the iOS Keychain. It is never written to the project, logs or commits.

## Build

Open `NativeCode.xcodeproj` in Xcode 26 or newer. The deployment target is iOS 26.

```bash
xcodebuild \
  -project NativeCode.xcodeproj \
  -scheme NativeCode \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

GitHub Actions also builds the simulator target, an unsigned device app and an unsigned IPA for LiveContainer.
