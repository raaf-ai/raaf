// Waits for globals that a CDN <script> defines.
//
// Three controllers here drive a library loaded from a tag at the end of the
// body: the diff viewer needs Diff and Diff2HtmlUI, the payload highlighter
// needs hljs, the tooltips need HSTooltip. Those tags are not guaranteed to
// have run when a controller connects, and a CDN is blocked outright on some
// networks, so each of them polls. Each used to carry its own copy of the same
// loop with a different budget and a different thing to do on giving up.
//
// Resolves when every name is on `window`; rejects once the budget is spent,
// so a caller can say so in the page rather than leave an empty box behind.
//
// @param names [Array<String>]
// @param attempts [Number] polls before giving up
// @param delay [Number] milliseconds between polls
// @return [Promise<void>]
function waitForGlobals(names, { attempts = 100, delay = 50 } = {}) {
  return new Promise((resolve, reject) => {
    let tries = 0

    const check = () => {
      if (names.every((name) => window[name])) return resolve()
      if (++tries > attempts) {
        return reject(new Error(`${names.join(", ")} did not load`))
      }
      setTimeout(check, delay)
    }

    check()
  })
}
