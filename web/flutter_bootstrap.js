{{flutter_js}}
{{flutter_build_config}}

// CanvasKit, the renderer, is loaded from this site rather than from Google's
// CDN, which is where Flutter fetches it by default. `flutter build web`
// always copies it into build/web/canvaskit/, so the app needs nothing from
// anywhere else to start.
_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
