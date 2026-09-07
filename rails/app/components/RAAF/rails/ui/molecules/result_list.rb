# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # ResultList — the hits a search span brought back.
        #
        # A search's payload is a ranked list, not a document, and printing it
        # as JSON in a PayloadBlock hides the two things a reader wants from it:
        # which pages came back, and in what order. So the positions are the
        # markup — numbered, titled, and linked out to the page itself.
        #
        # Only http(s) titles become links. A span's attributes are written by
        # whatever produced the span, so the URL is data rather than markup, and
        # a `javascript:` href in a console that renders traces from production
        # would be somebody else's script running on this page.
        #
        # @example
        #   render Molecules::ResultList.new(items: [
        #     { title: "Acme raises Series B", url: "https://example.com/acme",
        #       snippet: "The round was led by …", score: 0.82 }
        #   ])
        #
        class ResultList < Base
          LINKABLE = %r{\Ahttps?://}i

          # Long enough to judge a hit by, short enough that ten of them still
          # read as a list. The full text is in the Raw tab.
          SNIPPET_LIMIT = 320

          # @param items [Array<Hash>] :title, :url, :snippet, :score
          def initialize(items:, class: nil, **attrs)
            @items = Array(items)
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            ol(class: tokens("raaf-results", @class), **@attrs) do
              @items.each_with_index { |item, index| entry(item, index) }
            end
          end

          private

          def entry(item, index)
            li(class: "raaf-result") do
              div(class: "raaf-result-head") do
                span(class: "raaf-result-rank") { (index + 1).to_s }
                title_for(item)
                score_for(item, index)
              end
              url_for(item)
              snippet_for(item)
            end
          end

          # A hit with no title at all is still worth a row — it has a URL, and
          # the gap is itself information about what the provider returned.
          def title_for(item)
            label = item[:title].to_s.strip
            label = item[:url].to_s if label.empty?
            label = "(untitled)" if label.empty?

            if linkable?(item[:url])
              render Atoms::Link.new(label, href: item[:url], class: "raaf-result-title",
                                            target: "_blank", rel: "noopener noreferrer")
            else
              span(class: "raaf-result-title") { label }
            end
          end

          # Dropped when the score is only the position again — several
          # providers write the rank into the score field, and printing "3"
          # beside the 3 that already numbers the row says nothing twice.
          def score_for(item, index)
            score = item[:score]
            return if score.nil? || score.to_s.strip.empty?
            return if whole_number?(score) && score.to_i == index + 1

            render Atoms::Mono.new(format_score(score), tone: :muted,
                                                        class: "raaf-result-score")
          end

          # Shown even when the title already links to it: the host is how you
          # tell a vendor's own page from an aggregator repeating it.
          def url_for(item)
            url = item[:url].to_s
            return if url.empty?

            div(class: "raaf-result-url") { url }
          end

          def snippet_for(item)
            text = item[:snippet].to_s.strip
            return if text.empty?

            p(class: "raaf-result-snippet") { truncate_snippet(text) }
          end

          def truncate_snippet(text)
            return text if text.length <= SNIPPET_LIMIT

            "#{text[0, SNIPPET_LIMIT].rstrip}…"
          end

          def linkable?(url)
            url.to_s.match?(LINKABLE)
          end

          # Providers score on their own scales — a relevance of 0.4213, or a
          # rank written as 3.0. Fractions are cut to three places, where the
          # digits stop meaning anything; a whole number loses its decimal
          # point, because "3.000" reads as a measurement and it is a position.
          def format_score(score)
            return score.to_s unless score.is_a?(::Numeric)
            return score.to_i.to_s if whole_number?(score)

            score.to_f.round(3).to_s
          end

          def whole_number?(value)
            value.is_a?(::Numeric) && (value.to_f % 1).zero?
          end
        end
      end
    end
  end
end
