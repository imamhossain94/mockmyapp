MockMyApp is a free, open-source designer for App Store and Google Play screenshots. Put your app's screenshots into device frames, add backgrounds and captions, translate them, and export every size each store asks for. It runs on your own device, with no account and no server.

The web version also runs at **https://app.mockmyapp.com**, with nothing to install.

## What's new

This is the first release.

## Installing

### macOS

`MockMyApp-macOS.zip` · macOS 12 or later, Apple silicon and Intel

Unzip it and move MockMyApp to your Applications folder. The app isn't notarized by Apple, so macOS blocks it the first time you open it. On macOS 15 or later, try to open it once, then go to System Settings › Privacy & Security and click **Open Anyway**. On macOS 14 or earlier, right-click the app, choose **Open**, then click **Open** again.

### Windows

`MockMyApp-Windows.zip` · Windows 10 or later, 64-bit

Unzip it and run `mockmyapp.exe` from the `MockMyApp` folder, keeping the folder's files together. The app isn't code-signed, so SmartScreen may say "Windows protected your PC": click **More info**, then **Run anyway**.

### Linux

`MockMyApp-Linux.tar.gz` · 64-bit x86

It needs GTK 3, which most desktops already have (`libgtk-3-0` on Debian and Ubuntu). Extract it, then run the binary:

```
tar -xzf MockMyApp-Linux.tar.gz
./MockMyApp/mockmyapp
```

MP4 export uses an installed `ffmpeg` or GStreamer; without either, clips are exported as GIFs.

### Android

`MockMyApp-Android.apk` · Android 8 or later

Open the APK on your phone. Android asks you to allow installs from the app you opened it with, usually your browser or file manager; allow it, then install. MockMyApp isn't on Google Play, so updates don't arrive by themselves: install the next release's APK over this one.

### Web

`MockMyApp-Web.zip`

A static site, which can be served from any static web host. Unzip it and serve the files from the root of the site; to serve it from a sub-path, build it from source with `--base-href`. Opening `index.html` straight from the disk doesn't work.

## Privacy

MockMyApp collects nothing. There is no account, no analytics and no crash reporting, the app makes no network requests of its own, and your projects stay on your device. A few platform components can go online: on Android, Google's ML Kit downloads translation models and may send Google usage metrics; the operating system or the browser may download language packs and on-device AI models; and the web build fetches Noto fallback fonts for scripts the bundled fonts don't cover. The [README](https://github.com/imamhossain94/mockmyapp#privacy-what-goes-online) has the details.

## License

MockMyApp is open source under the MIT License. The source code is at https://github.com/imamhossain94/mockmyapp.
