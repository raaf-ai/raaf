// Preline's tooltips need one call to bind the markup the components render.
//
// This controller used to only log that it had connected, while the actual
// `autoInit()` sat in a separate inline script at the foot of every document
// that waited 500 ms and hoped. Preline is a CDN script tag like the rest, so
// it waits for the global the same way everything else here does.
class TooltipController extends Controller {
  connect() {
    waitForGlobals(["HSTooltip"], { attempts: 20, delay: 100 })
      .then(() => window.HSTooltip.autoInit())
      .catch(() => {
        // Tooltips are a nicety; every one of them has a visible label beside
        // it. Losing the CDN costs the hint, not the meaning.
      })
  }
}
