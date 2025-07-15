# frozen_string_literal: true

# Document libraries are loaded dynamically when needed

module RubyAIAgentsFactory
  module Tools
    # Document generation tool for creating PDFs, Word docs, and Excel files
    class DocumentTool
      attr_reader :name, :description, :output_dir

      def initialize(name: "generate_document", description: nil, output_dir: nil)
        @name = name
        @description = description || "Generate documents in various formats (PDF, Word, Excel)"
        @output_dir = output_dir || "./documents"

        ensure_output_dir
      end

      # Convert to tool definition for agents
      def to_tool_definition
        {
          type: "function",
          function: {
            name: @name,
            description: @description,
            parameters: {
              type: "object",
              properties: {
                format: {
                  type: "string",
                  description: "Document format",
                  enum: %w[pdf word excel csv]
                },
                filename: {
                  type: "string",
                  description: "Output filename (without extension)"
                },
                title: {
                  type: "string",
                  description: "Document title"
                },
                content: {
                  type: "object",
                  description: "Document content (structure depends on format)"
                },
                template: {
                  type: "string",
                  description: "Template name to use (optional)"
                }
              },
              required: %w[format filename content]
            }
          }
        }
      end

      # Generate document
      def call(arguments)
        format = arguments[:format] || arguments["format"]
        filename = arguments[:filename] || arguments["filename"]
        title = arguments[:title] || arguments["title"]
        content = arguments[:content] || arguments["content"]
        template = arguments[:template] || arguments["template"]

        begin
          filepath = case format.downcase
                     when "pdf"
                       generate_pdf(filename, title, content, template)
                     when "word", "docx"
                       generate_word(filename, title, content, template)
                     when "excel", "xlsx"
                       generate_excel(filename, title, content, template)
                     when "csv"
                       generate_csv(filename, content)
                     else
                       return { error: "Unsupported format: #{format}" }
                     end

          {
            success: true,
            format: format,
            filepath: filepath,
            size: File.size(filepath),
            created_at: Time.now.iso8601
          }
        rescue StandardError => e
          { error: "Document generation failed: #{e.message}" }
        end
      end

      private

      def ensure_output_dir
        FileUtils.mkdir_p(@output_dir)
      end

      def generate_pdf(filename, title, content, template)
        require "prawn" unless defined?(Prawn)
        filepath = File.join(@output_dir, "#{filename}.pdf")

        Prawn::Document.generate(filepath) do |pdf|
          # Apply template if provided
          apply_pdf_template(pdf, template) if template

          # Add title
          if title
            pdf.text title, size: 24, style: :bold
            pdf.move_down 20
          end

          # Add content based on structure
          case content
          when String
            pdf.text content
          when Array
            content.each do |section|
              add_pdf_section(pdf, section)
            end
          when Hash
            add_pdf_content(pdf, content)
          end
        end

        filepath
      end

      def add_pdf_section(pdf, section)
        case section
        when String
          pdf.text section
          pdf.move_down 10
        when Hash
          if section[:heading]
            pdf.text section[:heading], size: 18, style: :bold
            pdf.move_down 10
          end

          if section[:text]
            pdf.text section[:text]
            pdf.move_down 10
          end

          if section[:list]
            section[:list].each do |item|
              pdf.text "• #{item}", indent_paragraphs: 20
            end
            pdf.move_down 10
          end

          if section[:table]
            pdf.table section[:table][:data], header: section[:table][:headers]
            pdf.move_down 10
          end

          if section[:image] && File.exist?(section[:image])
            pdf.image section[:image], fit: [500, 300]
            pdf.move_down 10
          end
        end
      end

      def add_pdf_content(pdf, content)
        # Handle different content types
        content.each do |key, value|
          case key.to_s
          when "sections"
            value.each { |section| add_pdf_section(pdf, section) }
          when "text"
            pdf.text value
          when "metadata"
            # Add document properties
            pdf.info[:Title] = value[:title] if value[:title]
            pdf.info[:Author] = value[:author] if value[:author]
            pdf.info[:Subject] = value[:subject] if value[:subject]
          end
        end
      end

      def apply_pdf_template(pdf, template_name)
        # Load and apply template settings
        template_file = File.join(@output_dir, "templates", "#{template_name}.yml")

        return unless File.exist?(template_file)

        template = YAML.load_file(template_file)

        # Apply template settings
        pdf.font template["font"] if template["font"]
        pdf.default_leading template["line_spacing"] if template["line_spacing"]

        # Add header/footer if defined
        return unless template["header"]

        pdf.repeat(:all) do
          pdf.bounding_box([0, pdf.bounds.height], width: pdf.bounds.width, height: 50) do
            pdf.text template["header"], align: :center
          end
        end
      end

      def generate_word(filename, title, content, template)
        require "docx" unless defined?(Docx)
        filepath = File.join(@output_dir, "#{filename}.docx")

        # Create or load document
        doc = if template
                template_path = File.join(@output_dir, "templates", "#{template}.docx")
                File.exist?(template_path) ? Docx::Document.open(template_path) : Docx::Document.new
              else
                Docx::Document.new
              end

        # Add title
        if title
          doc.p title, style: "Heading1"
          doc.p "" # Empty paragraph
        end

        # Add content
        case content
        when String
          doc.p content
        when Array
          content.each do |section|
            add_word_section(doc, section)
          end
        when Hash
          add_word_content(doc, content)
        end

        doc.save(filepath)
        filepath
      end

      def add_word_section(doc, section)
        case section
        when String
          doc.p section
        when Hash
          doc.p section[:heading], style: "Heading2" if section[:heading]

          doc.p section[:text] if section[:text]

          section[:list]&.each do |item|
            doc.p "• #{item}"
          end

          if section[:table] && section[:table][:title]
            # Simple table support
            doc.p "Table: #{section[:table][:title]}"
            # NOTE: Complex table support would require additional implementation
          end
        end

        doc.p "" # Empty paragraph for spacing
      end

      def add_word_content(doc, content)
        content.each do |key, value|
          case key.to_s
          when "sections"
            value.each { |section| add_word_section(doc, section) }
          when "text"
            doc.p value
          when "paragraphs"
            value.each { |para| doc.p para }
          end
        end
      end

      def generate_excel(filename, title, content, template)
        require "rubyXL" unless defined?(RubyXL)
        filepath = File.join(@output_dir, "#{filename}.xlsx")

        workbook = RubyXL::Workbook.new

        # Apply template if provided
        apply_excel_template(workbook, template) if template

        # Process content
        case content
        when Hash
          if content[:sheets]
            # Multiple sheets
            content[:sheets].each_with_index do |sheet_data, index|
              sheet = index == 0 ? workbook[0] : workbook.add_worksheet(sheet_data[:name])
              sheet.sheet_name = sheet_data[:name] if sheet_data[:name]
              add_excel_sheet_content(sheet, sheet_data)
            end
          else
            # Single sheet
            sheet = workbook[0]
            sheet.sheet_name = title || "Sheet1"
            add_excel_sheet_content(sheet, { name: title || "Sheet1", data: content })
          end
        when Array
          # Single sheet with array data
          sheet = workbook[0]
          sheet.sheet_name = title || "Sheet1"
          add_excel_sheet_content(sheet, {
                                    name: title || "Sheet1",
                                    data: { rows: content }
                                  })
        end

        workbook.write(filepath)
        filepath
      end

      def add_excel_sheet_content(sheet, sheet_data)
        row_index = 0

        # Add title if provided
        if sheet_data[:title]
          sheet.add_cell(row_index, 0, sheet_data[:title])
          sheet.sheet_data[row_index][0].change_font_bold(true)
          sheet.sheet_data[row_index][0].change_font_size(16)
          row_index += 2 # Skip a row
        end

        data = sheet_data[:data]

        # Add headers if provided
        if data[:headers]
          data[:headers].each_with_index do |header, col|
            cell = sheet.add_cell(row_index, col, header)
            cell.change_font_bold(true)
            cell.change_fill("D0D0D0")
          end
          row_index += 1
        end

        # Add data rows
        data[:rows]&.each do |row|
          row.each_with_index do |value, col|
            sheet.add_cell(row_index, col, value)
          end
          row_index += 1
        end

        # Add formulas if provided
        return unless data[:formulas]

        data[:formulas].each do |formula_row|
          formula_row.each_with_index do |value, col|
            if value.is_a?(String) && value.start_with?("=")
              sheet.add_cell(row_index, col, "", value)
            else
              sheet.add_cell(row_index, col, value)
            end
          end
          row_index += 1
        end
      end

      def apply_excel_template(workbook, template_name)
        # Load template settings
        template_file = File.join(@output_dir, "templates", "#{template_name}.yml")

        return unless File.exist?(template_file)

        YAML.load_file(template_file)

        # RubyXL doesn't have direct properties support like Axlsx
        # Template settings would be applied differently
      end

      def generate_csv(filename, content)
        filepath = File.join(@output_dir, "#{filename}.csv")

        require "csv"

        CSV.open(filepath, "wb") do |csv|
          case content
          when Array
            content.each { |row| csv << row }
          when Hash
            # Add headers if provided
            csv << content[:headers] if content[:headers]

            # Add data rows
            content[:rows]&.each { |row| csv << row }
          end
        end

        filepath
      end
    end

    # Report generation tool with predefined templates
    class ReportTool < DocumentTool
      def initialize(name: "generate_report", **)
        super
        @description = "Generate formatted reports with charts and analytics"
      end

      def to_tool_definition
        definition = super
        definition[:function][:parameters][:properties][:report_type] = {
          type: "string",
          description: "Type of report",
          enum: %w[summary detailed analytics financial]
        }
        definition
      end

      def call(arguments)
        report_type = arguments[:report_type] || arguments["report_type"] || "summary"

        # Enhance content based on report type
        arguments = arguments.dup
        arguments[:content] = enhance_report_content(
          arguments[:content],
          report_type
        )

        super
      end

      private

      def enhance_report_content(content, report_type)
        case report_type
        when "summary"
          add_executive_summary(content)
        when "detailed"
          add_detailed_sections(content)
        when "analytics"
          add_charts_and_graphs(content)
        when "financial"
          add_financial_formatting(content)
        else
          content
        end
      end

      def add_executive_summary(content)
        {
          sections: [
            {
              heading: "Executive Summary",
              text: generate_summary(content),
              style: "highlight"
            }
          ] + (content[:sections] || [])
        }
      end

      def generate_summary(content)
        # Extract key points from content
        "This report summarizes the key findings and recommendations..."
      end

      def add_detailed_sections(content)
        # Add table of contents, appendices, etc.
        content
      end

      def add_charts_and_graphs(content)
        # Add data visualizations
        content
      end

      def add_financial_formatting(content)
        # Format numbers, add currency symbols, etc.
        content
      end
    end
  end
end
