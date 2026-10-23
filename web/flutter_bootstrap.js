{{flutter_js}}
{{flutter_build_config}}

// Serve CanvasKit from our own server (build/web/canvaskit) instead of
// Google's CDN, so the app doesn't depend on gstatic.com being reachable.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
