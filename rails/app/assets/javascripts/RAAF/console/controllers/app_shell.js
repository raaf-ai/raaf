// Shell — off-canvas sidebar on narrow viewports.
class AppShellController extends Controller {
  connect() {
    // Close the drawer after following a link, so the content is visible.
    this.element.addEventListener("click", (event) => {
      if (event.target.closest(".raaf-nav-item")) {
        this.element.classList.remove("is-nav-open")
      }
    })
  }

  toggleNav() {
    this.element.classList.toggle("is-nav-open")
  }

  closeNav() {
    this.element.classList.remove("is-nav-open")
  }
}
