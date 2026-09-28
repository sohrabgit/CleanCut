# CleanCut

On-device product-photo studio for iOS: background removal with Vision, studio compositing with Core Image and a custom Metal kernel, and marketplace-ready exports.

> 🚧 In active development — see [docs/SPEC.md](docs/SPEC.md) for the plan and [CHANGELOG.md](CHANGELOG.md) for progress.

## Build

```sh
brew install xcodegen
make generate   # creates CleanCut.xcodeproj from project.yml
make test       # runs the CleanCutKit test suite natively on macOS
open CleanCut.xcodeproj
```

Requires Xcode 26 · iOS 18+ · Swift 6.
