import { Controller } from "@hotwired/stimulus"

// NOTE: This controller is no longer used since percentage sampling was removed.
// Keeping as a stub for backwards compatibility.
// The form now always uses every_n sampling mode with a hidden field.
export default class extends Controller {
  connect() {
    // No-op - percentage sampling has been removed
  }
}
