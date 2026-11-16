# libxray sources

The c-shared library the simple portal runs. These are copies of the files the build actually
uses (`~/.hermes/cache/scratch/xraylib/build/libxray/`), kept in the repository because the
compiled `libxray.so` is gitignored and a release needs the sources that produced it.

- `main.go` — `XrayStart/XrayStop/XrayVersion`: the tunnel's core, started on a tun fd.
- `measure.go` — `XrayMeasure/XrayMeasureStop`: a separate instance slot that times every node
  with `core.Dial` + a forced outbound tag, no listeners, no tunnel.
- `jni_bridge.c` — the JNI names the plugin declares as `external fun`.

Build: `~/.hermes/cache/scratch/xraylib/build/xray-lib.sh` (pinned Xray v26.11.9, NDK 28.2,
API 26), then copy `libxray.so` into `android/app/src/main/jniLibs/arm64-v8a/`.
