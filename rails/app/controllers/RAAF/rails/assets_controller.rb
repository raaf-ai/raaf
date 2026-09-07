# frozen_string_literal: true

module RAAF
  module Rails
    # Serves the console's own stylesheet.
    #
    # The engine cannot assume the host application's asset pipeline — it may
    # be Sprockets, Propshaft, importmap or nothing at all — so the layout used
    # to inline the whole thing in a `<style>` element instead. That is correct
    # about the pipeline and expensive about everything else: 156 kB of CSS in
    # the document, regenerated and re-sent on every navigation, that a browser
    # has no way to keep.
    #
    # Serving it from the engine's own route needs no pipeline either, and the
    # path carries a content hash, so a browser fetches it once and the URL
    # changes by itself when the CSS does.
    class AssetsController < ApplicationController
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
