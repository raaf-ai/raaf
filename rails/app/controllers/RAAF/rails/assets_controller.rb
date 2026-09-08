# frozen_string_literal: true

module RAAF
  module Rails
    # Serves the console's own stylesheet and JavaScript.
    #
    # The engine cannot assume the host application's asset pipeline — it may
    # be Sprockets, Propshaft, importmap or nothing at all — so the layout used
    # to inline both of them in the document instead. That is correct about the
    # pipeline and expensive about everything else: 156 kB of CSS and 40 kB of
    # controllers, regenerated and re-sent on every navigation, that a browser
    # has no way to keep.
    #
    # Serving them from the engine's own routes needs no pipeline either, and
    # each path carries a content hash, so a browser fetches it once and the
    # URL changes by itself when the file does.
    class AssetsController < ApplicationController
      # Rails raises InvalidCrossOriginRequest on any non-XHR GET that answers
      # with a JavaScript media type, on the assumption the body was meant for
      # the session that asked and is worth stealing. This body is the console's
      # own Stimulus controllers: the same bytes for every visitor, holding
      # nothing that belongs to a session, and fetched in exactly the way that
      # check forbids -- by a <script> tag in the layout. Left on, it turned
      # every console page's JavaScript into a 422 and the console into a page
      # that renders and then does nothing.
      skip_after_action :verify_same_origin_request, only: :javascript

      # GET /assets/console-:digest.css
      #
      # The digest in the path is not read. It is there so the URL changes with
      # the content; this action always answers with the current stylesheet,
      # which is the only thing it could correctly answer with.
      def stylesheet
        css = Ui::Stylesheet.call

        response.set_header("Cache-Control", cache_control)
        render body: css, content_type: "text/css"
      end

      # GET /assets/console-:digest.js
      #
      # The console's Stimulus controllers, assembled into one ES module. The
      # digest is ignored here for the same reason as in {stylesheet}.
      def javascript
        response.set_header("Cache-Control", cache_control)
        render body: Ui::Javascript.call, content_type: "text/javascript"
      end

      private

      # Immutable, because the path names the content: a changed stylesheet is
      # a different URL and the stale copy is simply never requested again.
      #
      # Development is the exception. The digest still changes on every edit,
      # but a year-long immutable entry left behind by a branch you have since
      # switched away from is a bad afternoon, and there is nothing to save
      # over a loopback interface.
      def cache_control
        return "no-cache" if ::Rails.env.development? || ::Rails.env.test?

        "public, max-age=31536000, immutable"
      end
    end
  end
end
