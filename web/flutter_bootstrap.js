{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // Keep Flutter's dynamic Unicode fallback requests on the app origin.
    // The release bundles the fallback shards exercised by the supported QA
    // sample; an unbundled glyph fails locally instead of contacting a CDN.
    fontFallbackBaseUrl: 'fallback_fonts/',
  },
});
