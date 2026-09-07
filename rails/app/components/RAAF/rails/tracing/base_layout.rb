# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # BaseLayout — the document every dashboard page is rendered into.
      #
      # The shell is Shell.dc.html from the RAAF Console design: a 238px
      # sidebar of collapsible nav groups beside a sticky header carrying the
      # breadcrumb, title, time range, live toggle and search.
      #
      # Navigation is declared once here as NAV_GROUPS. An item without a
      # `href` renders as a "soon" placeholder, which is how the design shows
      # screens that do not exist yet — so this list doubles as the roadmap.
      #
      class BaseLayout < BaseComponent
        # Which nav item is current is read off the request path. The adapter
        # is what phlex-rails offers in place of reaching for the view context
        # directly; `helpers` is the same thing with a deprecation on it.
        include Phlex::Rails::Helpers::Request

        # @param range_href [#call, nil] receives a range, returns its URL.
        #   Without it the header leaves the time range out entirely, which is
        #   how a screen that does not filter by time opts out.
        # Front-end libraries a page can ask for by name.
        #
        # The head used to load all of them on every screen, so the Overview
        # paid for a megabyte of diff renderer it never called and the policy
        # list paid for a syntax highlighter with nothing to highlight. None of
        # the tags carried +defer+, so all of it blocked the first paint.
        # Measured against the CDNs on 2026-09-07: diff2html-ui 1,024 kB, its
        # stylesheet 17 kB, jsdiff 17 kB, highlight.js 122 kB and its JSON
        # grammar 0.5 kB — 1.18 MB that most of the console has no use for.
        #
        # A page names what it needs and pays for nothing else. The Stimulus
        # controllers that drive these libraries stay registered everywhere:
        # they are defined inline, cost nothing until an element asks for one,
        # and only a page that asked for the bundle carries such an element.
        #
        # No page asks for +:syntax+ on its own today. The components that print
        # a highlighted payload — +SpanDetail::Component+ and the per-kind
        # +*SpanComponent+ family — are orphaned: the console rebuild replaced
        # that screen with +Ui::Organisms::SpanInspector+, which renders a bare
        # +pre+ that +hljs.highlightAll+ does not even match, and nothing
        # constructs the old components any more. It stays a bundle because
        # +:diff+ depends on it and because those components are still here, so
        # whoever revives that screen finds the loader rather than the symptom.
        BUNDLES = %i[diff syntax].freeze

        # Bundles that pull in other bundles.
        #
        # diff2html ships three builds and they differ only in how much
        # highlighter they carry: the full one 1,024 kB, the slim one 291 kB,
        # the base one 92 kB. The base build takes an +hljs+ implementation as
        # its fourth constructor argument and +highlightCode+ throws without
        # one, so the console loads that and its own highlight.js rather than
        # a second copy welded into a megabyte bundle — 1,024 kB against the
        # 215 kB this pair costs, for the same diff.
        BUNDLE_DEPENDENCIES = { diff: %i[syntax] }.freeze

        # @param bundles [Array<Symbol>] any of {BUNDLES}; anything else is
        #   ignored rather than raised on, so a typo in a caller costs the page
        #   its highlighting instead of a 500.
        def initialize(title: "Overview", crumb: nil, current: nil, range: "24h",
                       range_href: nil, live: true, breadcrumb: nil, bundles: [])
          @title = title
          @crumb = crumb
          @current = current
          @range = range
          @range_href = range_href
          @live = live
          @breadcrumb = breadcrumb
          requested = Array(bundles).map(&:to_sym) & BUNDLES
          @bundles = requested.flat_map { |name| [ name, *BUNDLE_DEPENDENCIES[name] ] }.uniq
        end

        def view_template(&block)
          doctype
          html(lang: "en") do
            head { render_head }

            body(class: "raaf-root",
                 data: { controller: "auto-refresh tooltip", auto_refresh_interval_value: 30_000 }) do
              render(shell) { yield if block }
              render_scripts
            end
          end
        end

        private

        def render_head
          meta(charset: "utf-8")
          meta(name: "viewport", content: "width=device-width, initial-scale=1")
          title { "RAAF Console — #{@title}" }

          link(rel: "preconnect", href: "https://fonts.googleapis.com")
          link(rel: "preconnect", href: "https://fonts.gstatic.com", crossorigin: "anonymous")
          link(rel: "stylesheet",
               href: "https://fonts.googleapis.com/css2?family=Figtree:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500&display=swap")
          link(rel: "stylesheet",
               href: "https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css")

          if bundle?(:diff)
            link(rel: "stylesheet",
                 href: "https://cdn.jsdelivr.net/npm/diff2html@3.4.52/bundles/css/diff2html.min.css")
          end

          # MIGRATION SCAFFOLDING — remove once every page component has been
          # converted to the UI library. Pages still carrying Tailwind utility
          # classes depend on this; converted pages do not touch it.
          script(src: "https://cdn.tailwindcss.com")

          # Linked rather than inlined: 156 kB of CSS in every document, on
          # every navigation, that the browser could never keep. The path
          # carries the stylesheet's content hash, so this is fetched once and
          # re-fetched exactly when the CSS changes.
          link(rel: "stylesheet", href: console_stylesheet_path(Ui::Stylesheet.digest))

          csrf_meta_tags
          csp_meta_tag
        end

        # @param name [Symbol]
        # @return [Boolean] whether this page asked for that bundle
        def bundle?(name)
          @bundles.include?(name)
        end

        # jsdiff and diff2html, for the replay comparison view.
        #
        # The base diff2html build, which expects the highlighter to be handed
        # to it — +:diff+ brings +:syntax+ along for exactly that, and
        # +DiffController+ passes +window.hljs+ when it constructs the UI.
        # Its stylesheet is linked from the head; these go at the end of the
        # body, where they no longer hold up the first paint. The controller
        # polls for both globals, so arriving late costs it one 50 ms tick.
        def render_diff_bundle
          script(src: "https://cdn.jsdelivr.net/npm/diff@5.2.0/dist/diff.min.js")
          script(src: "https://cdn.jsdelivr.net/npm/diff2html@3.4.52/bundles/js/diff2html-ui-base.min.js")
        end

        # highlight.js and its JSON grammar, for the screens that print a
        # payload.
        #
        # No stylesheet comes with it: +molecules/syntax.css+ themes the
        # +.hljs-*+ classes for the console's own dark surface, scoped under
        # +.raaf-root+, so the CDN's default theme was loaded only to be
        # overridden by the inline stylesheet that follows it.
        def render_syntax_bundle
          script(src: "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js")
          script(src: "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/json.min.js")

          script do
            safe(<<~JS)
              document.addEventListener('DOMContentLoaded', function() {
                if (typeof hljs !== 'undefined') { hljs.highlightAll(); }
              });
            JS
          end
        end

        def shell
          Ui::Organisms::PageShell.new(
            sidebar: sidebar,
            title: @title,
            crumb: @crumb || crumb_from_nav,
            range: @range,
            range_href: @range_href,
            live: @live,
            search_href: tracing_search_path
          )
        end

        def sidebar
          Ui::Organisms::Sidebar.new(
            groups: nav_groups,
            current: @current || current_from_path,
            brand: "RAAF",
            subtitle: "Console",
            brand_href: dashboard_path,
            meta: "raaf-rails #{RAAF::Rails::VERSION} · #{::Rails.env}"
          )
        end

        # The console's navigation, straight from the design. Items without an
        # href are screens the engine does not route yet.
        def nav_groups
          [
            { id: :monitor, label: "Monitor", items: [
              { key: :overview, label: "Overview", icon: "grid-1x2", href: dashboard_path },
              { key: :agents, label: "Agents", icon: "cpu", href: dashboard_agents_path },
              { key: :performance, label: "Performance", icon: "speedometer2",
                href: dashboard_performance_path },
              { key: :errors, label: "Errors", icon: "exclamation-triangle", href: dashboard_errors_path },
              { key: :costs, label: "Cost & usage", icon: "cash-stack", href: dashboard_costs_path }
            ] },
            { id: :tracing, label: "Tracing", items: [
              { key: :traces, label: "Traces", icon: "diagram-3", href: tracing_traces_path },
              { key: :spans, label: "Spans", icon: "layers", href: tracing_spans_path },
              { key: :search, label: "Search", icon: "search", href: tracing_search_path },
              { key: :flows, label: "Flows", icon: "share", href: flows_tracing_spans_path },
              { key: :tools, label: "Tools", icon: "tools", href: tools_tracing_spans_path }
            ] },
            { id: :evaluate, label: "Evaluate", items: [
              { key: :datasets, label: "Datasets", icon: "collection", href: eval_datasets_path },
              { key: :experiments, label: "Experiments", icon: "eyedropper", href: eval_experiments_path },
              { key: :prompts, label: "Prompts", icon: "file-text", href: eval_prompts_path },
              { key: :feedback, label: "Feedback scores", icon: "hand-thumbs-up", href: eval_feedback_scores_path }
            ] },
            { id: :continuous, label: "Continuous", items: [
              { key: :policies, label: "Policies", icon: "clipboard-check", href: continuous_policies_path },
              { key: :queue, label: "Queue", icon: "hourglass-split",
                href: continuous_queue_index_path },
              { key: :results, label: "Results", icon: "list-check" },
              { key: :health, label: "Health", icon: "heart-pulse",
                href: continuous_health_path }
            ] },
            { id: :converse, label: "Conversations", items: [
              { key: :chat, label: "Chat", icon: "chat-dots" },
              { key: :replays, label: "Replays", icon: "arrow-repeat", href: tracing_replays_path }
            ] }
          ]
        end

        # Every routed item, flattened — used to resolve the active key and
        # the breadcrumb from the request path.
        def nav_items
          nav_groups.flat_map { |group| group[:items].map { |item| item.merge(group: group[:label]) } }
                    .select { |item| item[:href] }
        end

        # Longest matching href wins, so "/spans/tools" stays on Tools rather
        # than falling back to Spans.
        def current_from_path
          path = request_path
          return nil if path.blank?

          nav_items
            .select { |item| path == item[:href] || path.start_with?("#{item[:href]}/") }
            .max_by { |item| item[:href].length }
            &.fetch(:key)
        end

        def crumb_from_nav
          key = @current || current_from_path
          nav_items.find { |item| item[:key] == key }&.fetch(:group)
        end

        # Nil when there is no request to read — a component spec, or a render
        # outside a view context. A layout with no path simply has no current
        # nav item, which is the same answer as a path matching nothing.
        def request_path
          request&.path
        rescue StandardError
          nil
        end

        def render_scripts
          # Use ES6 modules to properly load and initialize Stimulus
          script(type: "module") do
            safe(<<~JS)
              // Import and initialize Stimulus properly
              import { Application, Controller } from "https://unpkg.com/@hotwired/stimulus/dist/stimulus.js"

              // Start Stimulus application
              const application = Application.start()

              // Register span-detail controller
              class SpanDetailController extends Controller {
                    static targets = ["toggleIcon", "section"]
                    static values = { debug: { type: Boolean, default: false } }

                    connect() {
                      if (this.debugValue) {
                        console.log("🔍 SpanDetail controller connected")
                      }
                      this.initializeSectionStates()
                    }

                    toggleSection(event) {
                      event.preventDefault()

                      const button = event.currentTarget
                      const targetId = button.dataset.target
                      const section = document.getElementById(targetId)
                      const previewSection = document.getElementById(targetId + '-preview')
                      const icon = button.querySelector('.toggle-icon')

                      // Check if this is an expandable text section (has both preview and full sections)
                      if (previewSection && section) {
                        this.toggleExpandableText(previewSection, section, button)
                        return
                      }

                      // Regular section toggle
                      if (!section) {
                        console.warn(`No section found with ID: ${targetId}`)
                        return
                      }

                      this.performToggle(section, icon, button)
                    }

                    toggleExpandableText(previewSection, fullSection, button) {
                      const isShowingPreview = !previewSection.classList.contains('hidden')

                      if (isShowingPreview) {
                        // Show full text, hide preview
                        previewSection.classList.add('hidden')
                        fullSection.classList.remove('hidden')
                        button.textContent = 'Show Less'
                      } else {
                        // Show preview, hide full text
                        previewSection.classList.remove('hidden')
                        fullSection.classList.add('hidden')
                        button.textContent = 'Show Full Text'
                      }

                      if (this.debugValue) {
                        console.log(`🔍 Toggled expandable text: showing ${isShowingPreview ? 'full' : 'preview'}`)
                      }
                    }

                    performToggle(section, icon, button) {
                      if (section.classList.contains('hidden')) {
                        section.classList.remove('hidden')
                        if (icon) {
                          icon.classList.remove('bi-chevron-right')
                          icon.classList.add('bi-chevron-down')
                        }
                      } else {
                        section.classList.add('hidden')
                        if (icon) {
                          icon.classList.remove('bi-chevron-down')
                          icon.classList.add('bi-chevron-right')
                        }
                      }
                    }

                    initializeSectionStates() {
                      const collapsedSections = this.element.querySelectorAll('[data-initially-collapsed="true"]')
                      collapsedSections.forEach(section => {
                        section.classList.add('hidden')
                      })
                    }

                    copyToClipboard(event) {
                      event.preventDefault()

                      const button = event.currentTarget
                      const value = button.dataset.value

                      if (!value) {
                        console.warn('No value found to copy')
                        return
                      }

                      navigator.clipboard.writeText(value).then(() => {
                        const icon = button.querySelector('i')
                        if (icon) {
                          icon.classList.remove('bi-clipboard')
                          icon.classList.add('bi-clipboard-check', 'text-green-600')

                          setTimeout(() => {
                            icon.classList.remove('bi-clipboard-check', 'text-green-600')
                            icon.classList.add('bi-clipboard')
                          }, 1500)
                        }
                      }).catch(err => {
                        console.error('Failed to copy value: ', err)
                      })
                    }

                    toggleValue(event) {
                      event.preventDefault()

                      const button = event.currentTarget
                      const targetId = button.dataset.target
                      const preview = document.getElementById(`${targetId}-preview`)
                      const full = document.getElementById(`${targetId}-full`)

                      if (this.debugValue) {
                        console.log(`🔍 toggleValue called with targetId: ${targetId}`)
                        console.log(`🔍 Looking for preview element: ${targetId}-preview`)
                        console.log(`🔍 Looking for full element: ${targetId}-full`)
                        console.log(`🔍 Preview element found:`, preview)
                        console.log(`🔍 Full element found:`, full)
                      }

                      if (!preview || !full) {
                        console.warn(`Value elements not found for: ${targetId}`)
                        console.warn(`Preview element (${targetId}-preview):`, preview)
                        console.warn(`Full element (${targetId}-full):`, full)
                        return
                      }

                      if (full.classList.contains('hidden')) {
                        preview.classList.add('hidden')
                        full.classList.remove('hidden')
                        // Store original text if not already stored
                        if (!button.dataset.originalText) {
                          button.dataset.originalText = button.textContent
                        }
                        button.textContent = 'Show Less'
                      } else {
                        preview.classList.remove('hidden')
                        full.classList.add('hidden')
                        // Restore original text if available, otherwise use generic text
                        button.textContent = button.dataset.originalText || 'Show More'
                      }

                      if (this.debugValue) {
                        console.log(`🔍 Toggle completed. Full element hidden: ${full.classList.contains('hidden')}`)
                      }
                    }

                    disconnect() {
                      if (this.debugValue) {
                        console.log("🔍 SpanDetail controller disconnected")
                      }
                    }
              }

              // Register auto-refresh controller (basic implementation)
              // Reloads the page on an interval. Previously each dashboard shipped
              // its own copy of this as an inline script; it now lives here once.
              class AutoRefreshController extends Controller {
                static values = { interval: Number, enabled: { type: Boolean, default: true } }
                static targets = ["indicator"]

                connect() {
                  this.boundVisibility = () => this.restart()
                  document.addEventListener("visibilitychange", this.boundVisibility)
                  this.restart()
                }

                disconnect() {
                  this.stop()
                  document.removeEventListener("visibilitychange", this.boundVisibility)
                }

                toggle(event) {
                  if (event) event.preventDefault()
                  this.enabledValue = !this.enabledValue
                  this.restart()
                }

                restart() {
                  this.stop()
                  // Don't burn requests refreshing a tab nobody is looking at.
                  if (!this.enabledValue || document.hidden || !this.intervalValue) return
                  this.timer = setInterval(() => window.location.reload(), this.intervalValue)
                  this.render()
                }

                stop() {
                  if (this.timer) clearInterval(this.timer)
                  this.timer = null
                  this.render()
                }

                // Keeps the label and class the shell served — the design
                // calls this control Live / Paused.
                render() {
                  this.indicatorTargets.forEach((el) => {
                    el.textContent = this.enabledValue ? "Live" : "Paused"
                    el.classList.toggle("is-live", this.enabledValue)
                  })
                }
              }

              // One policy watches one agent, so only one agent's checks may be
              // ticked. Switching agent reveals that agent's group and clears
              // every box outside it — a selection kept across a switch is
              // exactly what produced policies naming two agents, which match
              // no span at all.
              class PolicyAgentController extends Controller {
                static targets = ["select", "group"]

                // Only reveal on connect. Clearing here would silently untick
                // the checks a saved policy already has, which is a data loss
                // dressed up as a redraw.
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

              // A filter whose only control is a select: changing it should
              // apply, without an Apply button beside every one. Kept out of
              // an inline onchange so the markup carries no script.
              class AutoSubmitController extends Controller {
                submit() {
                  this.element.requestSubmit ? this.element.requestSubmit() : this.element.submit()
                }
              }

              // Reloads the page while a section is waiting on something a
              // worker will finish, so a result appears without anybody pressing
              // refresh. A reload keeps the scroll position and the fragment, so
              // the page comes back where it was rather than at the top. The
              // section decides when to stop by no longer asking for this.
              class SectionRefreshController extends Controller {
                static values = { interval: { type: Number, default: 5000 } }

                connect() {
                  this.timer = setInterval(() => {
                    if (!document.hidden) {
                      window.location.reload()
                    }
                  }, this.intervalValue)
                }

                disconnect() {
                  if (this.timer) {
                    clearInterval(this.timer)
                    this.timer = null
                  }
                }
              }

              // Register tooltip controller (basic implementation)
              class TooltipController extends Controller {
                connect() {
                  console.log("💬 Tooltip controller connected")
                }
              }

              // JSON highlighting controller
              class JsonHighlightController extends Controller {
                static targets = ["json"]

                connect() {
                  console.log("🎨 JSON highlight controller connected")
                  this.highlightAll()
                }

                highlightAll() {
                  this.jsonTargets.forEach(element => {
                    this.highlightElement(element)
                  })
                }

                highlightElement(element, attempt = 0) {
                  if (!window.hljs) {
                    // highlight.js only loads on pages that asked for the
                    // syntax bundle, and a CDN can fail anywhere. Give it two
                    // seconds, then leave the payload unhighlighted rather
                    // than polling this element for the life of the tab.
                    if (attempt >= 20) return
                    setTimeout(() => this.highlightElement(element, attempt + 1), 100)
                    return
                  }

                  try {
                    // Ensure the element has the correct class for JSON highlighting
                    element.classList.add('language-json')

                    // Apply syntax highlighting
                    window.hljs.highlightElement(element)

                    console.log("🎨 Applied JSON syntax highlighting to element")
                  } catch (error) {
                    console.warn('Failed to highlight JSON:', error)
                  }
                }
              }

              // Evaluator toggle controller (for policy form check selection)
              // Also handles showing/hiding the "Evaluate every" control based on trigger mode
              class EvaluatorToggleController extends Controller {
                static targets = ["checkbox", "config", "triggerMode", "samplingConfig"]

                connect() {
                  this.updateVisibility()
                  this.updateSamplingVisibility()
                }

                toggle() {
                  this.updateVisibility()
                }

                triggerModeChanged() {
                  this.updateSamplingVisibility()
                }

                updateVisibility() {
                  const isChecked = this.checkboxTarget.checked

                  if (isChecked) {
                    this.configTarget.classList.remove("hidden")
                    this.element.classList.add("bg-blue-50")
                    this.element.classList.remove("hover:bg-gray-50")
                  } else {
                    this.configTarget.classList.add("hidden")
                    this.element.classList.remove("bg-blue-50")
                    this.element.classList.add("hover:bg-gray-50")
                  }
                }

                updateSamplingVisibility() {
                  if (!this.hasTriggerModeTarget || !this.hasSamplingConfigTarget) {
                    return
                  }

                  const triggerMode = this.triggerModeTarget.value

                  if (triggerMode === "manual") {
                    this.samplingConfigTarget.classList.add("hidden")
                  } else {
                    this.samplingConfigTarget.classList.remove("hidden")
                  }
                }
              }

              // Check sampling controller (for per-check sampling mode toggle)
              class CheckSamplingController extends Controller {
                static targets = ["modeSelect", "percentageFields", "everyNFields"]

                connect() {
                  this.updateVisibility()
                }

                toggle() {
                  this.updateVisibility()
                }

                updateVisibility() {
                  if (!this.hasModeSelectTarget) return

                  const selectedMode = this.modeSelectTarget.value

                  if (this.hasPercentageFieldsTarget) {
                    if (selectedMode === "every_n") {
                      this.percentageFieldsTarget.classList.add("hidden")
                    } else {
                      this.percentageFieldsTarget.classList.remove("hidden")
                    }
                  }

                  if (this.hasEveryNFieldsTarget) {
                    if (selectedMode === "every_n") {
                      this.everyNFieldsTarget.classList.remove("hidden")
                    } else {
                      this.everyNFieldsTarget.classList.add("hidden")
                    }
                  }
                }
              }

              // Replay form controller - handles provider/model selection and form submission
              class ReplayFormController extends Controller {
                static targets = [
                  "provider",
                  "model",
                  "temperature",
                  "temperatureValue",
                  "maxTokens",
                  "topP",
                  "topPValue",
                  "frequencyPenalty",
                  "frequencyPenaltyValue",
                  "presencePenalty",
                  "presencePenaltyValue"
                ]

                static values = {
                  submitUrl: String,
                  spanId: String,
                  debug: { type: Boolean, default: false }
                }

                // Model definitions by provider
                static models = {
                  openai: [
                    // GPT-5 Series (Latest)
                    { value: "gpt-5", label: "GPT-5" },
                    // GPT-4.1 Series (April 2025)
                    { value: "gpt-4.1", label: "GPT-4.1" },
                    { value: "gpt-4.1-mini", label: "GPT-4.1 Mini" },
                    { value: "gpt-4.1-nano", label: "GPT-4.1 Nano" },
                    // GPT-4o Series
                    { value: "gpt-4o", label: "GPT-4o" },
                    { value: "gpt-4o-mini", label: "GPT-4o Mini" },
                    { value: "gpt-4-turbo", label: "GPT-4 Turbo" },
                    // O-Series Reasoning Models
                    { value: "o3-pro", label: "O3 Pro" },
                    { value: "o3", label: "O3" },
                    { value: "o4-mini", label: "O4 Mini" },
                    { value: "o1-preview", label: "O1 Preview" },
                    { value: "o1-mini", label: "O1 Mini" },
                    { value: "o3-mini", label: "O3 Mini" }
                  ],
                  anthropic: [
                    { value: "claude-sonnet-4-20250514", label: "Claude 4 Sonnet" },
                    { value: "claude-3-5-sonnet-20241022", label: "Claude 3.5 Sonnet" },
                    { value: "claude-3-opus-20240229", label: "Claude 3 Opus" },
                    { value: "claude-3-5-haiku-20241022", label: "Claude 3.5 Haiku" }
                  ],
                  google: [
                    { value: "gemini-3-pro-preview", label: "Gemini 3 Pro Preview" },
                    { value: "gemini-3-flash-preview", label: "Gemini 3 Flash Preview" },
                    { value: "gemini-2.5-pro", label: "Gemini 2.5 Pro" },
                    { value: "gemini-2.5-flash", label: "Gemini 2.5 Flash" },
                    { value: "gemini-2.5-flash-lite", label: "Gemini 2.5 Flash Lite" },
                    { value: "gemini-2.0-flash", label: "Gemini 2.0 Flash" },
                    { value: "gemini-2.0-flash-lite", label: "Gemini 2.0 Flash Lite" }
                  ],
                  perplexity: [
                    { value: "sonar-pro", label: "Sonar Pro" },
                    { value: "sonar", label: "Sonar" },
                    { value: "sonar-reasoning-pro", label: "Sonar Reasoning Pro" },
                    { value: "sonar-reasoning", label: "Sonar Reasoning" }
                  ],
                  groq: [
                    { value: "llama-3.3-70b-versatile", label: "Llama 3.3 70B" },
                    { value: "llama-3.1-70b-versatile", label: "Llama 3.1 70B" },
                    { value: "llama-3.1-8b-instant", label: "Llama 3.1 8B" },
                    { value: "mixtral-8x7b-32768", label: "Mixtral 8x7B" }
                  ],
                  xai: [
                    { value: "grok-2-1212", label: "Grok 2" },
                    { value: "grok-2-vision-1212", label: "Grok 2 Vision" },
                    { value: "grok-beta", label: "Grok Beta" }
                  ]
                }

                connect() {
                  if (this.debugValue) {
                    console.log("Replay form controller connected")
                  }

                  // Initialize model filtering based on current provider selection
                  if (this.hasProviderTarget && this.hasModelTarget) {
                    this.updateModelOptions()
                  }
                }

                // Rebuild model dropdown with only models for the selected provider
                updateModelOptions() {
                  if (!this.hasProviderTarget || !this.hasModelTarget) {
                    return
                  }

                  const selectedProvider = this.providerTarget.value
                  const modelSelect = this.modelTarget
                  const currentModel = modelSelect.value
                  const models = this.constructor.models[selectedProvider] || []

                  if (this.debugValue) {
                    console.log("Updating models for provider:", selectedProvider, models)
                  }

                  // Clear existing options
                  modelSelect.innerHTML = ""

                  // Add new options for the selected provider
                  let selectedFound = false
                  models.forEach((model, index) => {
                    const option = document.createElement("option")
                    option.value = model.value
                    option.textContent = model.label

                    // Try to preserve current selection if it exists in the new provider
                    if (model.value === currentModel) {
                      option.selected = true
                      selectedFound = true
                    } else if (index === 0 && !selectedFound) {
                      // Select first option by default
                      option.selected = true
                    }

                    modelSelect.appendChild(option)
                  })

                  if (this.debugValue) {
                    console.log("Model dropdown updated, selected:", modelSelect.value)
                  }
                }

                // Update slider value display when slider changes
                updateSliderValue(event) {
                  const slider = event.currentTarget
                  const name = slider.name
                  const value = slider.value

                  // Find the corresponding value display element
                  const valueDisplay = document.getElementById(name + "-value")
                  if (valueDisplay) {
                    valueDisplay.textContent = value
                  }

                  if (this.debugValue) {
                    console.log("Slider " + name + " updated to " + value)
                  }
                }

                // Collect form data and submit via Turbo
                submit(event) {
                  event.preventDefault()

                  const formData = this.collectFormData()

                  if (this.debugValue) {
                    console.log("Submitting replay with data:", formData)
                  }

                  this.submitReplay(formData)
                }

                // Collect all form data
                collectFormData() {
                  const data = {
                    span_replay: {
                      configuration_changes: {},
                      system_prompt: null,
                      user_messages: []
                    }
                  }

                  // Collect provider and model settings
                  if (this.hasProviderTarget) {
                    data.span_replay.configuration_changes.provider = this.providerTarget.value
                  }

                  if (this.hasModelTarget) {
                    data.span_replay.configuration_changes.model = this.modelTarget.value
                  }

                  if (this.hasTemperatureTarget) {
                    data.span_replay.configuration_changes.temperature = parseFloat(this.temperatureTarget.value)
                  }

                  if (this.hasMaxTokensTarget) {
                    data.span_replay.configuration_changes.max_tokens = parseInt(this.maxTokensTarget.value, 10)
                  }

                  if (this.hasTopPTarget) {
                    data.span_replay.configuration_changes.top_p = parseFloat(this.topPTarget.value)
                  }

                  if (this.hasFrequencyPenaltyTarget) {
                    data.span_replay.configuration_changes.frequency_penalty = parseFloat(this.frequencyPenaltyTarget.value)
                  }

                  if (this.hasPresencePenaltyTarget) {
                    data.span_replay.configuration_changes.presence_penalty = parseFloat(this.presencePenaltyTarget.value)
                  }

                  // Collect system prompt
                  const systemPrompt = document.getElementById("system_prompt")
                  if (systemPrompt) {
                    data.span_replay.system_prompt = systemPrompt.value
                  }

                  // Collect user messages
                  const messagesContainer = document.getElementById("messages-container")
                  if (messagesContainer) {
                    const messageFields = messagesContainer.querySelectorAll("[data-message-index]")
                    messageFields.forEach((field) => {
                      const textarea = field.querySelector("textarea")
                      const roleInput = field.querySelector("input[type='hidden']")
                      if (textarea && roleInput) {
                        data.span_replay.user_messages.push({
                          role: roleInput.value,
                          content: textarea.value
                        })
                      }
                    })
                  }

                  // Collect notes
                  const notesField = document.getElementById("notes")
                  if (notesField) {
                    data.span_replay.notes = notesField.value
                  }

                  return data
                }

                // Submit the replay request
                async submitReplay(formData) {
                  const statusContainer = document.getElementById("replay-status")

                  // Show loading state
                  if (statusContainer) {
                    statusContainer.innerHTML =
                      '<div class="raaf-alert raaf-alert--info" role="status">' +
                        '<span class="raaf-icon"><i class="bi bi-arrow-repeat"></i></span>' +
                        '<div class="raaf-alert-body">' +
                          '<p class="raaf-alert-title">Starting</p>' +
                          '<p class="raaf-alert-text">Queueing the replay…</p>' +
                        '</div>' +
                      '</div>'
                  }

                  try {
                    // Get the form element to extract the URL
                    const form = this.element.closest("form") || document.querySelector("form")
                    const url = form ? form.action : this.submitUrlValue

                    const response = await fetch(url, {
                      method: "POST",
                      headers: {
                        "Content-Type": "application/json",
                        "Accept": "application/json, text/vnd.turbo-stream.html, text/html",
                        "X-CSRF-Token": this.getCsrfToken()
                      },
                      body: JSON.stringify(formData)
                    })

                    if (response.ok) {
                      const contentType = response.headers.get("content-type")

                      if (contentType && contentType.includes("text/vnd.turbo-stream.html")) {
                        // Handle Turbo Stream response - apply it then redirect to show page
                        const html = await response.text()
                        // Use window.Turbo if available (set by @hotwired/turbo-rails)
                        if (typeof window !== 'undefined' && window.Turbo && window.Turbo.renderStreamMessage) {
                          window.Turbo.renderStreamMessage(html)
                        }

                        // Extract replay_id from the turbo-stream response and redirect to show page
                        // The stream HTML contains the replay ID in the target element
                        const parser = new DOMParser()
                        const doc = parser.parseFromString(html, 'text/html')
                        const streamEl = doc.querySelector('turbo-stream')

                        // Try to extract replay_id from the response
                        const replayIdMatch = html.match(/replay[_-]?(\\d+)/i) || html.match(/replays\\/(\\d+)/)
                        if (replayIdMatch && replayIdMatch[1]) {
                          const replayId = replayIdMatch[1]
                          const currentPath = window.location.pathname
                          // Convert /new to /:id in the URL path
                          const showPath = currentPath.replace(/\\/new$/, '/' + replayId)
                          console.log("🚀 Redirecting to replay show page:", showPath)
                          setTimeout(() => { window.location.href = showPath }, 500)
                        } else {
                          console.log("✅ Replay created, status updated in place")
                        }
                      } else if (contentType && contentType.includes("application/json")) {
                        // Handle JSON response - redirect to show page
                        const result = await response.json()
                        if (result.replay_id) {
                          window.location.href = result.redirect_url || window.location.pathname.replace("/new", "/" + result.replay_id)
                        }
                      } else {
                        // Handle HTML response
                        const html = await response.text()
                        if (statusContainer) {
                          statusContainer.innerHTML = html
                        }
                      }
                    } else {
                      throw new Error("Request failed with status " + response.status)
                    }
                  } catch (error) {
                    console.error("Replay submission failed:", error)

                    if (statusContainer) {
                      statusContainer.innerHTML =
                        '<div class="raaf-alert raaf-alert--error" role="alert">' +
                          '<span class="raaf-icon"><i class="bi bi-x-octagon-fill"></i></span>' +
                          '<div class="raaf-alert-body">' +
                            '<p class="raaf-alert-title">The replay could not be queued</p>' +
                            '<p class="raaf-alert-text"></p>' +
                          '</div>' +
                        '</div>'
                      statusContainer.querySelector(".raaf-alert-text").textContent = error.message
                    }
                  }
                }

                getCsrfToken() {
                  const meta = document.querySelector('meta[name="csrf-token"]')
                  return meta ? meta.getAttribute("content") : ""
                }

                disconnect() {
                  if (this.debugValue) {
                    console.log("Replay form controller disconnected")
                  }
                }
              }

              // Prompt editor — add and remove user messages on the replay form.
              // The replay form reads the messages straight out of the DOM, so a
              // row added here only has to carry the same shape as one rendered
              // by the server: a role, a textarea, and an index.
              class PromptEditorController extends Controller {
                static targets = ["messages", "empty"]

                addMessage(event) {
                  event.preventDefault()
                  if (!this.hasMessagesTarget) return

                  const index = this.messagesTarget.querySelectorAll("[data-message-index]").length
                  const row = document.createElement("div")
                  row.className = "raaf-msg"
                  row.dataset.messageIndex = index
                  row.innerHTML =
                    '<div class="raaf-msg-head">' +
                      '<span class="raaf-msg-role">user</span>' +
                      '<button type="button" class="raaf-msg-remove" aria-label="Remove message" ' +
                        'data-action="click->prompt-editor#removeMessage"><i class="bi bi-x-lg"></i></button>' +
                    '</div>' +
                    '<textarea rows="4" name="user_messages[' + index + '][content]" ' +
                      'class="raaf-input raaf-input--glass raaf-textarea raaf-input--mono"></textarea>' +
                    '<input type="hidden" name="user_messages[' + index + '][role]" value="user">'

                  this.messagesTarget.appendChild(row)
                  this.toggleEmpty()
                  row.querySelector("textarea").focus()
                }

                removeMessage(event) {
                  event.preventDefault()
                  const row = event.currentTarget.closest("[data-message-index]")
                  if (row) row.remove()
                  this.reindex()
                  this.toggleEmpty()
                }

                // Field names carry the index, so removing the first of three
                // messages would otherwise post 1 and 2 with no 0 between them.
                reindex() {
                  if (!this.hasMessagesTarget) return

                  this.messagesTarget.querySelectorAll("[data-message-index]").forEach((row, index) => {
                    row.dataset.messageIndex = index
                    const body = row.querySelector("textarea")
                    const role = row.querySelector("input[type='hidden']")
                    if (body) body.name = "user_messages[" + index + "][content]"
                    if (role) role.name = "user_messages[" + index + "][role]"
                  })
                }

                toggleEmpty() {
                  if (!this.hasEmptyTarget || !this.hasMessagesTarget) return

                  const any = this.messagesTarget.querySelectorAll("[data-message-index]").length > 0
                  this.emptyTarget.classList.toggle("hidden", any)
                }
              }

              // Diff controller for showing differences between original and replayed output
              // Uses global Diff and Diff2HtmlUI from CDN scripts
              class DiffController extends Controller {
                static targets = ["container"]
                static values = {
                  original: String,
                  replayed: String,
                  outputStyle: { type: String, default: "side-by-side" }
                }

                connect() {
                  console.log("🔍 Diff controller connected")
                  // Wait for libraries to load. They come from a CDN, so say
                  // so in the container when they never arrive rather than
                  // leaving the reader looking at an empty box.
                  this.waitForLibraries()
                    .then(() => this.renderDiff())
                    .catch((error) => {
                      console.warn("Diff libraries unavailable:", error)
                      if (this.hasContainerTarget) {
                        this.containerTarget.textContent =
                          "Could not load the diff viewer. Check the network tab for a blocked CDN request."
                      }
                    })
                }

                waitForLibraries() {
                  return new Promise((resolve, reject) => {
                    // hljs is in the list because the base diff2html build has
                    // no highlighter of its own -- highlightCode() throws
                    // without the one handed to the constructor.
                    let attempts = 0
                    const check = () => {
                      if (window.Diff && window.Diff2HtmlUI && window.hljs) {
                        resolve()
                      } else if (++attempts > 200) {
                        reject(new Error("diff libraries did not load"))
                      } else {
                        setTimeout(check, 50)
                      }
                    }
                    check()
                  })
                }

                renderDiff() {
                  const original = this.originalValue || ""
                  const replayed = this.replayedValue || ""

                  if (!original && !replayed) {
                    this.containerTarget.innerHTML = '<p class="text-gray-500 italic p-4">No output to compare</p>'
                    return
                  }

                  // Create unified diff using the global Diff library
                  const unifiedDiff = window.Diff.createTwoFilesPatch(
                    "original",
                    "replayed",
                    original,
                    replayed,
                    "Original Output",
                    "Replayed Output",
                    { context: 3 }
                  )

                  // Render with diff2html (global Diff2HtmlUI)
                  const diff2htmlUi = new window.Diff2HtmlUI(this.containerTarget, unifiedDiff, {
                    drawFileList: false,
                    matching: "lines",
                    outputFormat: this.outputStyleValue === "line-by-line" ? "line-by-line" : "side-by-side",
                    highlight: true,
                    renderNothingWhenEmpty: false
                  }, window.hljs)

                  diff2htmlUi.draw()
                  diff2htmlUi.highlightCode()
                  console.log("✅ Diff rendered successfully")
                }

                toggleView(event) {
                  const newStyle = event.params.outputStyle || "side-by-side"
                  this.outputStyleValue = newStyle

                  // The toggle is a tab strip from the library, so the active
                  // one is marked the way every other tab in the console is.
                  const button = event.currentTarget
                  button.parentElement.querySelectorAll(".raaf-tab").forEach(tab => {
                    const active = tab === button
                    tab.classList.toggle("is-active", active)
                    tab.setAttribute("aria-selected", active ? "true" : "false")
                  })

                  this.renderDiff()
                }
              }

              // Poll controller for auto-refreshing replay status
              class PollController extends Controller {
                static values = {
                  url: String,
                  interval: { type: Number, default: 2000 }
                }

                connect() {
                  console.log("🔄 Poll controller connected, polling", this.urlValue, "every", this.intervalValue, "ms")
                  this.poll()
                }

                disconnect() {
                  if (this.timer) {
                    clearTimeout(this.timer)
                  }
                }

                poll() {
                  fetch(this.urlValue, {
                    headers: { "Accept": "application/json" }
                  })
                    .then(response => response.json())
                    .then(data => {
                      console.log("📊 Poll response:", data.status)
                      if (data.status === "completed" || data.status === "failed") {
                        // Reload the page to show the final result
                        console.log("✅ Replay finished, reloading page...")
                        window.location.reload()
                      } else {
                        // Continue polling
                        this.timer = setTimeout(() => this.poll(), this.intervalValue)
                      }
                    })
                    .catch(error => {
                      console.error("Poll error:", error)
                      // Retry on error
                      this.timer = setTimeout(() => this.poll(), this.intervalValue)
                    })
                }
              }

              // Shell — off-canvas sidebar on narrow viewports.
              class AppShellController extends Controller {
                toggleNav() {
                  this.element.classList.toggle("is-nav-open")
                }

                closeNav() {
                  this.element.classList.remove("is-nav-open")
                }

                // Close the drawer after following a link, so the content is visible.
                connect() {
                  this.element.addEventListener("click", (event) => {
                    if (event.target.closest(".raaf-nav-item")) {
                      this.element.classList.remove("is-nav-open")
                    }
                  })
                }
              }

              // Experiment editor — the diff rail, the weights total and the
              // trigger, from the isEdit screen in RAAF Eval.dc.html.
              //
              // Every editable control carries the label and the value it was
              // loaded with, so the diff compares each field against its own
              // `data-diff-initial` rather than against a second copy of the
              // record kept in the page.
              class ExperimentEditController extends Controller {
                static targets = [
                  "field", "changes", "changesEmpty", "dirtyBadge",
                  "temperatureValue", "weightTotal", "scorerRow", "cron"
                ]
                static values = { fullWeight: Number }

                connect() {
                  this.render()
                  this.element.addEventListener("input", () => this.render())
                  this.element.addEventListener("change", () => this.render())
                }

                revert() {
                  this.fieldTargets.forEach((field) => this.reset(field))
                  this.render()
                }

                temperatureChanged() { this.render() }

                triggerChanged() { this.render() }

                // A scorer switched off keeps its numbers — they are what it
                // will use again — and only loses the row's emphasis.
                scorerToggled(event) {
                  const row = event.target.closest("[data-experiment-edit-target='scorerRow']")
                  if (row) row.classList.toggle("is-off", !event.target.checked)
                }

                render() {
                  this.renderTemperature()
                  this.renderWeightTotal()
                  this.renderCronState()
                  this.renderChanges()
                }

                renderTemperature() {
                  if (!this.hasTemperatureValueTarget) return
                  const slider = this.element.querySelector("input[type='range']")
                  if (slider) this.temperatureValueTarget.textContent = Number(slider.value).toFixed(2)
                }

                // Only enabled scorers count, so switching one off cannot make
                // a valid set look wrong.
                renderWeightTotal() {
                  if (!this.hasWeightTotalTarget) return

                  let total = 0
                  this.scorerRowTargets.forEach((row) => {
                    const on = row.querySelector("input[type='checkbox']")
                    const weight = row.querySelector("input[name$='[weight]']")
                    if (on && on.checked && weight) total += Number(weight.value || 0)
                  })

                  this.weightTotalTarget.textContent = `weights total ${total.toFixed(2)}`
                  const full = this.hasFullWeightValue ? this.fullWeightValue : 1
                  this.weightTotalTarget.classList.toggle(
                    "raaf-weight-total--off", Math.abs(total - full) > 0.001
                  )
                }

                renderCronState() {
                  if (!this.hasCronTarget) return
                  const trigger = this.element.querySelector(
                    "input[name$='[trigger]']:checked"
                  )
                  this.cronTarget.disabled = !trigger || trigger.value !== "cron"
                }

                renderChanges() {
                  if (!this.hasChangesTarget) return

                  const changes = this.fieldTargets
                    .map((field) => this.change(field))
                    .filter((change) => change !== null)

                  this.changesTarget.replaceChildren(
                    ...changes.map((change) => this.row(change))
                  )

                  if (this.hasChangesEmptyTarget) {
                    this.changesEmptyTarget.hidden = changes.length > 0
                  }
                  if (this.hasDirtyBadgeTarget) {
                    this.dirtyBadgeTarget.textContent =
                      changes.length === 0
                        ? "Saved"
                        : `${changes.length} change${changes.length === 1 ? "" : "s"}`
                  }
                }

                change(field) {
                  const from = field.dataset.diffInitial ?? ""
                  const to = this.currentValue(field)
                  // An unselected radio has nothing to compare; only the
                  // checked one in a group speaks for the group.
                  if (to === null || from === to) return null
                  return { label: field.dataset.diffLabel || field.name, from, to }
                }

                currentValue(field) {
                  if (field.type === "checkbox") return field.checked ? "on" : "off"
                  if (field.type === "radio") return field.checked ? this.pillLabel(field) : null
                  if (field.tagName === "SELECT") {
                    return field.selectedOptions[0] ? field.selectedOptions[0].textContent.trim() : ""
                  }
                  return field.value
                }

                // A trigger reads as its pill, not as its stored value — the
                // diff should say what the screen says.
                pillLabel(radio) {
                  const label = this.element.querySelector(`label[for='${radio.id}']`)
                  return label ? label.textContent.trim() : radio.value
                }

                reset(field) {
                  const initial = field.dataset.diffInitial ?? ""
                  if (field.type === "checkbox") {
                    field.checked = initial === "on"
                    field.dispatchEvent(new Event("change", { bubbles: true }))
                  } else if (field.type === "radio") {
                    field.checked = this.pillLabel(field) === initial
                  } else if (field.tagName === "SELECT") {
                    // A select is tracked by its option's text, because that is
                    // what the diff shows — assigning that text as the value
                    // would clear the selection instead of restoring it.
                    const options = [...field.options]
                    const option =
                      options.find((o) => o.textContent.trim() === initial) ||
                      options.find((o) => o.value === "")
                    if (option) field.selectedIndex = option.index
                  } else {
                    field.value = initial
                  }
                }

                row(change) {
                  const row = document.createElement("div")
                  row.className = "raaf-diff-row"

                  const label = document.createElement("span")
                  label.className = "raaf-diff-label"
                  label.textContent = change.label

                  const values = document.createElement("div")
                  values.className = "raaf-diff-values"

                  const from = document.createElement("span")
                  from.className = "raaf-diff-from"
                  from.textContent = change.from === "" ? "empty" : change.from

                  const arrow = document.createElement("i")
                  arrow.className = "bi bi-arrow-right-short raaf-diff-arrow"

                  const to = document.createElement("span")
                  to.className = "raaf-diff-to"
                  to.textContent = change.to === "" ? "empty" : change.to

                  values.append(from, arrow, to)
                  row.append(label, values)
                  return row
                }
              }

              // Register all controllers
              application.register("experiment-edit", ExperimentEditController)
              application.register("app-shell", AppShellController)
              application.register("span-detail", SpanDetailController)
              application.register("auto-refresh", AutoRefreshController)
              application.register("section-refresh", SectionRefreshController)
              application.register("auto-submit", AutoSubmitController)
              application.register("policy-agent", PolicyAgentController)
              application.register("tooltip", TooltipController)
              application.register("json-highlight", JsonHighlightController)
              application.register("evaluator-toggle", EvaluatorToggleController)
              application.register("check-sampling", CheckSamplingController)
              application.register("replay-form", ReplayFormController)
              application.register("prompt-editor", PromptEditorController)
              application.register("poll", PollController)
              application.register("diff", DiffController)

              console.log("✅ All RAAF Stimulus controllers registered")
            JS
          end

          # Syntax first: the base diff2html build is handed the highlighter
          # rather than carrying one.
          render_syntax_bundle if bundle?(:syntax)
          render_diff_bundle if bundle?(:diff)

          # Preline JS
          script(src: "https://preline.co/assets/js/preline.js")

          # Debug script for tooltip troubleshooting
          script do
            safe(<<~JS)
              // Debug tooltips after all scripts load
              window.addEventListener('load', function() {
                console.log('🔧 RAAF Tooltip Debug: Window loaded');

                setTimeout(function() {
                  // Check if Preline is loaded
                  if (typeof window.HSTooltip !== 'undefined') {
                    console.log('✅ HSTooltip available:', typeof window.HSTooltip);

                    try {
                      window.HSTooltip.autoInit();
                      console.log('✅ HSTooltip.autoInit() called');
                    } catch (e) {
                      console.error('❌ HSTooltip.autoInit() error:', e);
                    }

                    // Count tooltip elements
                    const tooltips = document.querySelectorAll('.hs-tooltip');
                    const toggles = document.querySelectorAll('.hs-tooltip-toggle');
                    console.log(`🎯 Found ${tooltips.length} tooltip containers, ${toggles.length} toggles`);

                  } else {
                    console.warn('⚠️ HSTooltip not available');
                    console.log('Available HS objects:', Object.keys(window).filter(k => k.startsWith('HS')));
                  }
                }, 500);
              });
            JS
          end
        end
      end
    end
  end
end
