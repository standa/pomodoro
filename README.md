# Pomodoro


<img width="167" height="217" alt="image" src="https://github.com/user-attachments/assets/8a7b94b0-dbfa-4e21-a4c0-56b6b12598ec" />

<img width="231" height="139" alt="image" src="https://github.com/user-attachments/assets/5f407133-9845-4087-9fd3-f8f1f1e244fe" />


A tiny macOS menu bar pomodoro timer: a ~200 KB app with no dependencies.

- 15, 25 or 50 minute pomodoros. There's no pause: Stop throws the pomodoro away.
- When a pomodoro ends, a dialog on every screen asks whether to start a break. Breaks are 5 min (10 after a 50), with 15 min after every 4th pomodoro.
- Daily counter (`3/10`) that resets at midnight.
- A small always-on-top window with an editable "current task" line.
- Runs off the clock and saves every change, so sleep, quitting or a crash doesn't lose your place.

## Install

Download `Pomodoro-vX.Y.Z.zip` from [Releases](https://github.com/standa/pomodoro/releases), unzip it and move `Pomodoro.app` to Applications.

The app isn't notarized, so macOS blocks it on first launch. Either open **System Settings → Privacy & Security** and click **Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Pomodoro.app
```

## Build

Requires the Xcode Command Line Tools. Runs the tests, then builds a universal `build/Pomodoro.app`:

```sh
./build.sh           # build
./build.sh install   # build, copy to ~/Applications and launch
```

## Release

```sh
git tag v1.0.0 && git push origin v1.0.0
```

The GitHub workflow tests, builds and publishes a release with the zipped app attached.
