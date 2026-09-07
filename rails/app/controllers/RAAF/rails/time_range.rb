# frozen_string_literal: true

module RAAF
  module Rails
    ##
    # The topbar's time range control, shared by every screen that filters by
    # time.
    #
    # The four labels are also the URL value, so a chosen range survives a
    # link, a refresh and a bookmark rather than living as component state that
    # each screen would re-derive. Three controllers used to carry their own
    # copy of `parse_time_range`, which is why the control could be wired on
    # one screen and inert on the next.
    #
    # A range the reader picks is also remembered in the session, so it holds
    # while they move around. The console is read by walking it — spend looks
    # wrong, so open Agents, then Traces, then one trace — and the sidebar
    # links carry no query string, so without this every step reset the window
    # to the default and quietly answered a different question than the one
    # just asked.
    #
    # The URL still wins over the memory, which keeps a shared or bookmarked
    # link honest: it shows what it says, and picking it up also becomes the
    # reader's new remembered range.
    #
    # Everything here is private, so including it does not turn `current_range`
    # and friends into routable actions.
    #
    module TimeRange
      RANGES = { "1h" => 1.hour, "24h" => 24.hours, "7d" => 7.days, "30d" => 30.days }.freeze

      # Namespaced, because this session belongs to the host application and
      # the console is only a guest in it.
      SESSION_KEY = "raaf_range"

      private

      # Overridden where a screen opens on a different window — the continuous
      # console reads a week, because a policy sampling a few spans an hour
      # says nothing over a day.
      def default_range
        "24h"
      end

      # The range this request is answering for.
      #
      # An explicit choice in the URL wins and is remembered; failing that the
      # range last chosen; failing that the screen's own default. Anything
      # that is not one of the four the control offers is ignored rather than
      # raising, in the URL and in the session alike: the first arrives from a
      # link anyone can edit, and the second may have been written by an older
      # version of this console.
      def current_range
        return @current_range if defined?(@current_range)

        @current_range =
          if RANGES.key?(params[:range])
            remember_range(params[:range])
          else
            remembered_range || default_range
          end
      end

      # The range last explicitly chosen, or nil if there is none to honour.
      def remembered_range
        value = range_session&.[](SESSION_KEY)
        value if RANGES.key?(value)
      end

      # Records an explicit choice and returns it, so the caller reads as one
      # expression.
      def remember_range(value)
        session = range_session
        session[SESSION_KEY] = value if session

        value
      end

      # The session, when there is one to use.
      #
      # A host can mount this engine in an application with sessions disabled,
      # and a range control is not worth a 500 — without one the range simply
      # stops being sticky and every other behaviour is unchanged.
      def range_session
        return nil unless respond_to?(:session, true)

        session
      rescue StandardError
        nil
      end

      def range_duration
        RANGES.fetch(current_range)
      end

      # Every other parameter is kept, so switching the range on a filtered
      # screen does not silently drop the filter, the tab or the trace.
      def range_href
        ->(value) { "#{request.path}?#{request.query_parameters.merge('range' => value).to_query}" }
      end

      # An explicit start_time/end_time still wins, so a link built before the
      # range control existed keeps working.
      def parse_time_range(params)
        start_time = params[:start_time].present? ? Time.zone.parse(params[:start_time]) : range_duration.ago
        end_time = params[:end_time].present? ? Time.zone.parse(params[:end_time]) : Time.current

        start_time..end_time
      rescue ArgumentError
        range_duration.ago..Time.current
      end
    end
  end
end
