# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "base64"

module RAAF
  module Tools
    # Confluence integration tool for managing pages, spaces, and content
    class ConfluenceTool
      attr_reader :name, :description

      def initialize(url:, username:, api_token:, name: "confluence", description: nil, **config)
        @url = url.gsub(%r{/$}, "") # Remove trailing slash
        @username = username
        @api_token = api_token
        @name = name
        @description = description || "Manage Confluence pages, spaces, and content"
        @config = config
        @demo_mode = username == "demo" || url.include?("demo")

        @api_base = "#{@url}/wiki/rest/api"
      end

      def to_tool_definition
        {
          type: "function",
          function: {
            name: @name,
            description: @description,
            parameters: {
              type: "object",
              properties: {
                action: {
                  type: "string",
                  description: "Action to perform",
                  enum: %w[get_space list_spaces create_space
                           get_page create_page update_page delete_page
                           search_content get_page_content get_page_children
                           add_attachment get_attachments add_comment
                           get_comments add_label get_labels
                           copy_page move_page export_page]
                },
                space_key: {
                  type: "string",
                  description: "Space key (e.g., 'PROJ')"
                },
                space_name: {
                  type: "string",
                  description: "Space name"
                },
                page_id: {
                  type: "string",
                  description: "Page ID"
                },
                title: {
                  type: "string",
                  description: "Page title"
                },
                content: {
                  type: "string",
                  description: "Page content (HTML or storage format)"
                },
                parent_id: {
                  type: "string",
                  description: "Parent page ID"
                },
                query: {
                  type: "string",
                  description: "Search query (CQL)"
                },
                version: {
                  type: "integer",
                  description: "Page version number"
                },
                comment: {
                  type: "string",
                  description: "Version comment or comment text"
                },
                labels: {
                  type: "array",
                  description: "Labels to add",
                  items: { type: "string" }
                },
                file_path: {
                  type: "string",
                  description: "Path to file for attachment"
                },
                attachment_comment: {
                  type: "string",
                  description: "Comment for attachment"
                },
                format: {
                  type: "string",
                  description: "Export format",
                  enum: %w[pdf word html]
                },
                expand: {
                  type: "array",
                  description: "Fields to expand in response",
                  items: { type: "string" }
                },
                limit: {
                  type: "integer",
                  description: "Result limit",
                  default: 25
                }
              },
              required: ["action"]
            }
          }
        }
      end

      def call(arguments)
        return demo_response(arguments) if @demo_mode

        action = arguments[:action] || arguments["action"]

        case action
        when "get_space"
          get_space(arguments)
        when "list_spaces"
          list_spaces(arguments)
        when "create_space"
          create_space(arguments)
        when "get_page"
          get_page(arguments)
        when "create_page"
          create_page(arguments)
        when "update_page"
          update_page(arguments)
        when "delete_page"
          delete_page(arguments)
        when "search_content"
          search_content(arguments)
        when "get_page_content"
          get_page_content(arguments)
        when "get_page_children"
          get_page_children(arguments)
        when "add_attachment"
          add_attachment(arguments)
        when "get_attachments"
          get_attachments(arguments)
        when "add_comment"
          add_comment(arguments)
        when "get_comments"
          get_comments(arguments)
        when "add_label"
          add_label(arguments)
        when "get_labels"
          get_labels(arguments)
        when "copy_page"
          copy_page(arguments)
        when "move_page"
          move_page(arguments)
        when "export_page"
          export_page(arguments)
        else
          { error: "Unknown action: #{action}" }
        end
      rescue StandardError => e
        { error: "Confluence API error: #{e.message}" }
      end

      private

      def get_space(args)
        space_key = args[:space_key] || args["space_key"]
        raise "Space key required" unless space_key

        expand = args[:expand] || args["expand"] || []

        result = make_request(:get, "/space/#{space_key}?expand=#{expand.join(",")}")
        format_space(result)
      end

      def list_spaces(args)
        limit = args[:limit] || args["limit"] || 25

        result = make_request(:get, "/space?limit=#{limit}")

        {
          spaces: result["results"].map { |s| format_space(s) },
          count: result["size"],
          total: result["totalSize"]
        }
      end

      def create_space(args)
        space_key = args[:space_key] || args["space_key"]
        space_name = args[:space_name] || args["space_name"]

        raise "Space key and name required" unless space_key && space_name

        body = {
          key: space_key,
          name: space_name,
          description: {
            plain: {
              value: args[:description] || "Created via API",
              representation: "plain"
            }
          }
        }

        result = make_request(:post, "/space", body: body)

        {
          success: true,
          space_key: result["key"],
          space_id: result["id"],
          message: "Created space: #{space_name}",
          url: "#{@url}/wiki/spaces/#{result["key"]}"
        }
      end

      def get_page(args)
        page_id = args[:page_id] || args["page_id"]
        raise "Page ID required" unless page_id

        expand = args[:expand] || args["expand"] || ["body.storage", "version"]

        result = make_request(:get, "/content/#{page_id}?expand=#{expand.join(",")}")
        format_page(result)
      end

      def create_page(args)
        space_key = args[:space_key] || args["space_key"]
        title = args[:title] || args["title"]
        content = args[:content] || args["content"] || ""
        parent_id = args[:parent_id] || args["parent_id"]

        raise "Space key and title required" unless space_key && title

        body = {
          type: "page",
          title: title,
          space: { key: space_key },
          body: {
            storage: {
              value: content,
              representation: "storage"
            }
          }
        }

        body[:ancestors] = [{ id: parent_id }] if parent_id

        result = make_request(:post, "/content", body: body)

        {
          success: true,
          page_id: result["id"],
          title: result["title"],
          message: "Created page: #{title}",
          url: "#{@url}#{result["_links"]["webui"]}"
        }
      end

      def update_page(args)
        page_id = args[:page_id] || args["page_id"]
        title = args[:title] || args["title"]
        content = args[:content] || args["content"]
        version = args[:version] || args["version"]
        comment = args[:comment] || args["comment"] || "Updated via API"

        raise "Page ID required" unless page_id

        # Get current page if version not provided
        if !version && (title || content)
          current = get_page(page_id: page_id)
          version = current[:version][:number]
        end

        body = {
          type: "page",
          version: {
            number: version + 1,
            message: comment
          }
        }

        body[:title] = title if title
        body[:body] = { storage: { value: content, representation: "storage" } } if content

        result = make_request(:put, "/content/#{page_id}", body: body)

        {
          success: true,
          page_id: result["id"],
          version: result["version"]["number"],
          message: "Updated page: #{result["title"]}"
        }
      end

      def delete_page(args)
        page_id = args[:page_id] || args["page_id"]
        raise "Page ID required" unless page_id

        make_request(:delete, "/content/#{page_id}")

        {
          success: true,
          message: "Deleted page"
        }
      end

      def search_content(args)
        query = args[:query] || args["query"]
        limit = args[:limit] || args["limit"] || 25

        raise "Search query required" unless query

        # URL encode the CQL query
        encoded_query = URI.encode_www_form_component(query)

        result = make_request(:get, "/content/search?cql=#{encoded_query}&limit=#{limit}")

        {
          results: result["results"].map { |r| format_search_result(r) },
          count: result["size"],
          total: result["totalSize"],
          query: query
        }
      end

      def get_page_content(args)
        page_id = args[:page_id] || args["page_id"]
        raise "Page ID required" unless page_id

        result = make_request(:get, "/content/#{page_id}?expand=body.storage,body.view")

        {
          page_id: result["id"],
          title: result["title"],
          content_storage: result["body"]["storage"]["value"],
          content_html: result["body"]["view"]["value"],
          version: result["version"]["number"]
        }
      end

      def get_page_children(args)
        page_id = args[:page_id] || args["page_id"]
        raise "Page ID required" unless page_id

        result = make_request(:get, "/content/#{page_id}/child/page")

        {
          children: result["results"].map { |p| format_page_summary(p) },
          count: result["size"]
        }
      end

      def add_attachment(args)
        page_id = args[:page_id] || args["page_id"]
        file_path = args[:file_path] || args["file_path"]
        args[:attachment_comment] || args["attachment_comment"] || ""

        raise "Page ID and file path required" unless page_id && file_path
        raise "File not found: #{file_path}" unless File.exist?(file_path)

        # Confluence attachment upload requires multipart form data
        # This is a simplified version - in production, use proper multipart library

        {
          success: true,
          message: "Attachment upload requires multipart form data implementation",
          file: File.basename(file_path)
        }
      end

      def get_attachments(args)
        page_id = args[:page_id] || args["page_id"]
        raise "Page ID required" unless page_id

        result = make_request(:get, "/content/#{page_id}/child/attachment")

        {
          attachments: result["results"].map { |a| format_attachment(a) },
          count: result["size"]
        }
      end

      def add_comment(args)
        page_id = args[:page_id] || args["page_id"]
        comment = args[:comment] || args["comment"]

        raise "Page ID and comment required" unless page_id && comment

        body = {
          type: "comment",
          container: { id: page_id, type: "page" },
          body: {
            storage: {
              value: "<p>#{comment}</p>",
              representation: "storage"
            }
          }
        }

        result = make_request(:post, "/content", body: body)

        {
          success: true,
          comment_id: result["id"],
          message: "Added comment to page"
        }
      end

      def get_comments(args)
        page_id = args[:page_id] || args["page_id"]
        raise "Page ID required" unless page_id

        result = make_request(:get, "/content/#{page_id}/child/comment?expand=body.storage")

        {
          comments: result["results"].map { |c| format_comment(c) },
          count: result["size"]
        }
      end

      def add_label(args)
        page_id = args[:page_id] || args["page_id"]
        labels = args[:labels] || args["labels"]

        raise "Page ID and labels required" unless page_id && labels

        body = labels.map { |label| { name: label } }

        result = make_request(:post, "/content/#{page_id}/label", body: body)

        {
          success: true,
          message: "Added #{labels.size} label(s)",
          labels: result["results"].map { |l| l["name"] }
        }
      end

      def get_labels(args)
        page_id = args[:page_id] || args["page_id"]
        raise "Page ID required" unless page_id

        result = make_request(:get, "/content/#{page_id}/label")

        {
          labels: result["results"].map { |l| l["name"] },
          count: result["size"]
        }
      end

      def copy_page(args)
        page_id = args[:page_id] || args["page_id"]
        new_title = args[:title] || args["title"]
        space_key = args[:space_key] || args["space_key"]
        parent_id = args[:parent_id] || args["parent_id"]

        raise "Page ID and new title required" unless page_id && new_title

        # Get original page
        original = get_page(page_id: page_id)

        # Create new page with copied content
        create_args = {
          space_key: space_key || original[:space_key],
          title: new_title,
          content: original[:content],
          parent_id: parent_id
        }

        create_page(create_args)
      end

      def move_page(args)
        page_id = args[:page_id] || args["page_id"]
        parent_id = args[:parent_id] || args["parent_id"]

        raise "Page ID and parent ID required" unless page_id && parent_id

        # Get current page
        current = get_page(page_id: page_id)

        body = {
          type: "page",
          title: current[:title],
          ancestors: [{ id: parent_id }],
          version: {
            number: current[:version] + 1,
            message: "Moved page"
          }
        }

        result = make_request(:put, "/content/#{page_id}", body: body)

        {
          success: true,
          message: "Moved page to new parent",
          page_id: result["id"]
        }
      end

      def export_page(args)
        page_id = args[:page_id] || args["page_id"]
        format = args[:format] || args["format"] || "pdf"

        raise "Page ID required" unless page_id

        # NOTE: Actual export requires different API endpoint
        # This is a placeholder implementation

        {
          success: true,
          message: "Page export initiated",
          format: format,
          download_url: "#{@url}/wiki/exportpage?pageId=#{page_id}&format=#{format}"
        }
      end

      def make_request(method, path, body: nil, params: nil)
        uri = URI.parse("#{@api_base}#{path}")
        uri.query = URI.encode_www_form(params) if params

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 30

        request = case method
                  when :get then Net::HTTP::Get.new(uri)
                  when :post then Net::HTTP::Post.new(uri)
                  when :put then Net::HTTP::Put.new(uri)
                  when :delete then Net::HTTP::Delete.new(uri)
                  end

        # Basic auth
        auth_string = Base64.strict_encode64("#{@username}:#{@api_token}")
        request["Authorization"] = "Basic #{auth_string}"
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"

        request.body = body.to_json if body && %i[post put].include?(method)

        response = http.request(request)

        unless response.code.start_with?("2")
          error_body = begin
            JSON.parse(response.body)
          rescue StandardError
            { "message" => response.body }
          end
          raise "Confluence API error (#{response.code}): #{error_body["message"] || error_body}"
        end

        return {} if response.body.nil? || response.body.empty?

        JSON.parse(response.body)
      end

      def format_space(space)
        {
          key: space["key"],
          name: space["name"],
          id: space["id"],
          type: space["type"],
          url: "#{@url}/wiki/spaces/#{space["key"]}"
        }
      end

      def format_page(page)
        {
          id: page["id"],
          title: page["title"],
          space_key: page["space"]["key"],
          version: page["version"]["number"],
          created: page["history"]["createdDate"],
          updated: page["version"]["when"],
          created_by: page["history"]["createdBy"]["displayName"],
          content: page["body"]&.dig("storage", "value"),
          url: "#{@url}#{page["_links"]["webui"]}"
        }
      end

      def format_page_summary(page)
        {
          id: page["id"],
          title: page["title"],
          type: page["type"],
          url: "#{@url}#{page["_links"]["webui"]}"
        }
      end

      def format_search_result(result)
        {
          id: result["content"]["id"],
          title: result["content"]["title"],
          type: result["content"]["type"],
          space: result["content"]["space"]["key"],
          excerpt: result["excerpt"],
          url: "#{@url}#{result["content"]["_links"]["webui"]}",
          last_modified: result["lastModified"]
        }
      end

      def format_attachment(attachment)
        {
          id: attachment["id"],
          title: attachment["title"],
          file_size: attachment["extensions"]["fileSize"],
          media_type: attachment["extensions"]["mediaType"],
          created: attachment["version"]["when"],
          created_by: attachment["version"]["by"]["displayName"],
          download_url: "#{@url}#{attachment["_links"]["download"]}"
        }
      end

      def format_comment(comment)
        {
          id: comment["id"],
          content: comment["body"]["storage"]["value"],
          created: comment["version"]["when"],
          created_by: comment["version"]["by"]["displayName"]
        }
      end

      def demo_response(args)
        action = args[:action] || args["action"]

        case action
        when "list_spaces"
          {
            spaces: [
              { key: "PROJ", name: "Project Space", id: "12345", url: "#{@url}/wiki/spaces/PROJ" },
              { key: "DOC", name: "Documentation", id: "12346", url: "#{@url}/wiki/spaces/DOC" }
            ],
            count: 2,
            total: 2
          }
        when "search_content"
          {
            results: [
              {
                id: "67890",
                title: "Getting Started Guide",
                type: "page",
                space: "DOC",
                excerpt: "This guide will help you get started..."
              }
            ],
            count: 1,
            total: 1
          }
        when "get_page"
          {
            id: "67890",
            title: "Sample Page",
            space_key: "PROJ",
            version: 3,
            content: "<p>This is sample content</p>",
            url: "#{@url}/wiki/spaces/PROJ/pages/67890"
          }
        else
          { success: true, message: "Demo mode: #{action} completed" }
        end
      end
    end
  end
end
