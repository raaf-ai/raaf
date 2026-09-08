// One policy watches one agent, so only one agent's checks may be ticked.
// Switching agent reveals that agent's group and clears every box outside it —
// a selection kept across a switch is exactly what produced policies naming
// two agents, which match no span at all.
class PolicyAgentController extends Controller {
  static targets = ["select", "group"]

  // Only reveal on connect. Clearing here would silently untick the checks a
  // saved policy already has, which is a data loss dressed up as a redraw.
  connect() { this.reveal(false) }

  select() { this.reveal(true) }

  reveal(clearHidden) {
    const chosen = this.hasSelectTarget ? this.selectTarget.value : null

    this.groupTargets.forEach((group) => {
      const mine = group.dataset.agent === chosen
      group.classList.toggle("hidden", !mine)
      if (!mine && clearHidden) this.clear(group)
    })
  }

  clear(group) {
    group.querySelectorAll('input[type="checkbox"]').forEach((box) => {
      if (!box.checked) return
      box.checked = false
      box.dispatchEvent(new Event("change", { bubbles: true }))
    })
  }
}
