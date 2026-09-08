// A filter whose only control is a select: changing it should apply, without
// an Apply button beside every one. Kept out of an inline onchange so the
// markup carries no script.
class AutoSubmitController extends Controller {
  submit() {
    this.element.requestSubmit ? this.element.requestSubmit() : this.element.submit()
  }
}
