# frozen_string_literal: true

require "base64"
require "net/http"
require "tempfile"
require "mimemagic"
require_relative "agent"
require_relative "function_tool"

module OpenAIAgents
  # Multi-modal support for agents (vision, audio, documents)
  module MultiModal
    # Multi-modal agent with vision and audio capabilities
    class MultiModalAgent < ::OpenAIAgents::Agent
      def initialize(**args)
        super(**args)
        @vision_enabled = true
        @audio_enabled = true
        @document_enabled = true
        setup_multi_modal_tools
      end
      
      private
      
      def setup_multi_modal_tools
        # Add vision tool
        add_tool(VisionTool.new)
        
        # Add audio tool
        add_tool(AudioTool.new)
        
        # Add document tool
        add_tool(DocumentTool.new)
      end
    end
    
    # Vision processing tool
    class VisionTool < ::OpenAIAgents::FunctionTool
      def initialize
        super(
          method(:analyze_image),
          name: "analyze_image",
          description: "Analyze and describe images, extract text, or answer questions about visual content"
        )
      end
      
      def analyze_image(image_path: nil, image_url: nil, question: nil)
        # Validate inputs
        unless image_path || image_url
          return { error: "Either image_path or image_url must be provided" }
        end
        
        begin
          # Prepare image data
          image_data = if image_path
                        encode_image_from_path(image_path)
                      else
                        encode_image_from_url(image_url)
                      end
          
          # Create vision-enabled message
          messages = build_vision_messages(image_data, question)
          
          # Call vision model
          response = call_vision_api(messages)
          
          {
            success: true,
            description: response,
            metadata: {
              source: image_path || image_url,
              analyzed_at: Time.now.iso8601
            }
          }
        rescue => e
          { error: e.message }
        end
      end
      
      private
      
      def encode_image_from_path(path)
        raise "Image file not found: #{path}" unless File.exist?(path)
        
        image_data = File.binread(path)
        mime_type = detect_mime_type(path)
        
        {
          data: Base64.strict_encode64(image_data),
          mime_type: mime_type
        }
      end
      
      def encode_image_from_url(url)
        uri = URI(url)
        response = Net::HTTP.get_response(uri)
        
        raise "Failed to fetch image: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
        
        mime_type = response['content-type'] || 'image/jpeg'
        
        {
          data: Base64.strict_encode64(response.body),
          mime_type: mime_type
        }
      end
      
      def detect_mime_type(path)
        mime = MimeMagic.by_path(path) || MimeMagic.by_magic(File.open(path))
        mime&.type || 'image/jpeg'
      end
      
      def build_vision_messages(image_data, question)
        content = []
        
        # Add question if provided
        if question
          content << {
            type: "text",
            text: question
          }
        else
          content << {
            type: "text",
            text: "What's in this image? Please describe it in detail."
          }
        end
        
        # Add image
        content << {
          type: "image_url",
          image_url: {
            url: "data:#{image_data[:mime_type]};base64,#{image_data[:data]}"
          }
        }
        
        [
          {
            role: "user",
            content: content
          }
        ]
      end
      
      def call_vision_api(messages)
        client = OpenAI::Client.new
        response = client.chat(
          parameters: {
            model: "gpt-4-vision-preview",
            messages: messages,
            max_tokens: 1000
          }
        )
        
        response.dig("choices", 0, "message", "content")
      end
    end
    
    # Audio processing tool
    class AudioTool < ::OpenAIAgents::FunctionTool
      def initialize
        super(
          method(:process_audio),
          name: "process_audio",
          description: "Transcribe speech, analyze audio content, or generate speech from text"
        )
      end
      
      def process_audio(action:, audio_path: nil, text: nil, voice: "alloy", language: "en")
        case action
        when "transcribe"
          transcribe_audio(audio_path, language)
        when "generate_speech"
          generate_speech(text, voice)
        when "analyze"
          analyze_audio(audio_path)
        else
          { error: "Unknown action: #{action}. Use 'transcribe', 'generate_speech', or 'analyze'" }
        end
      end
      
      private
      
      def transcribe_audio(audio_path, language)
        raise "Audio file not found: #{audio_path}" unless File.exist?(audio_path)
        
        client = OpenAI::Client.new
        
        File.open(audio_path, "rb") do |file|
          response = client.transcribe(
            parameters: {
              model: "whisper-1",
              file: file,
              language: language
            }
          )
          
          {
            success: true,
            text: response["text"],
            language: language,
            duration: get_audio_duration(audio_path)
          }
        end
      rescue => e
        { error: e.message }
      end
      
      def generate_speech(text, voice)
        raise "Text is required for speech generation" if text.nil? || text.empty?
        
        client = OpenAI::Client.new
        
        response = client.audio.speech(
          parameters: {
            model: "tts-1",
            input: text,
            voice: voice
          }
        )
        
        # Save to temporary file
        temp_file = Tempfile.new(["speech", ".mp3"])
        temp_file.binmode
        temp_file.write(response)
        temp_file.close
        
        {
          success: true,
          audio_path: temp_file.path,
          text_length: text.length,
          voice: voice
        }
      rescue => e
        { error: e.message }
      end
      
      def analyze_audio(audio_path)
        # First transcribe
        transcription = transcribe_audio(audio_path, "en")
        return transcription if transcription[:error]
        
        # Analyze the transcription
        analysis = analyze_transcript(transcription[:text])
        
        {
          success: true,
          transcription: transcription[:text],
          analysis: analysis,
          duration: transcription[:duration]
        }
      end
      
      def analyze_transcript(text)
        # Simple analysis - in production, use more sophisticated NLP
        {
          word_count: text.split.size,
          sentiment: detect_sentiment(text),
          key_topics: extract_topics(text),
          language_confidence: 0.95
        }
      end
      
      def detect_sentiment(text)
        # Simplified sentiment detection
        positive_words = %w[good great excellent happy wonderful]
        negative_words = %w[bad poor terrible sad awful]
        
        words = text.downcase.split
        positive_count = words.count { |w| positive_words.include?(w) }
        negative_count = words.count { |w| negative_words.include?(w) }
        
        if positive_count > negative_count
          "positive"
        elsif negative_count > positive_count
          "negative"
        else
          "neutral"
        end
      end
      
      def extract_topics(text)
        # Simple keyword extraction
        words = text.downcase.split(/\W+/)
        word_freq = words.tally
        word_freq.sort_by { |_, count| -count }.first(5).map(&:first)
      end
      
      def get_audio_duration(audio_path)
        # Simplified - in production use proper audio library
        File.size(audio_path) / 16000.0  # Rough estimate
      end
    end
    
    # Document processing tool
    class DocumentTool < ::OpenAIAgents::FunctionTool
      def initialize
        super(
          method(:process_document),
          name: "process_document",
          description: "Extract text from documents, analyze structure, or answer questions about document content"
        )
      end
      
      def process_document(document_path:, action: "extract", query: nil)
        raise "Document not found: #{document_path}" unless File.exist?(document_path)
        
        case action
        when "extract"
          extract_text(document_path)
        when "analyze"
          analyze_document(document_path)
        when "query"
          query_document(document_path, query)
        else
          { error: "Unknown action: #{action}" }
        end
      end
      
      private
      
      def extract_text(document_path)
        extension = File.extname(document_path).downcase
        
        text = case extension
               when ".txt"
                 File.read(document_path)
               when ".pdf"
                 extract_pdf_text(document_path)
               when ".docx"
                 extract_docx_text(document_path)
               when ".html", ".htm"
                 extract_html_text(document_path)
               else
                 return { error: "Unsupported document type: #{extension}" }
               end
        
        {
          success: true,
          text: text,
          metadata: {
            filename: File.basename(document_path),
            size: File.size(document_path),
            type: extension,
            extracted_at: Time.now.iso8601
          }
        }
      rescue => e
        { error: e.message }
      end
      
      def extract_pdf_text(path)
        # Simplified - in production use PDF parsing library
        "PDF content extraction would happen here"
      end
      
      def extract_docx_text(path)
        # Simplified - in production use DOCX parsing library
        "DOCX content extraction would happen here"
      end
      
      def extract_html_text(path)
        html = File.read(path)
        # Simple HTML tag removal
        html.gsub(/<[^>]*>/, ' ').gsub(/\s+/, ' ').strip
      end
      
      def analyze_document(document_path)
        # Extract text first
        extraction = extract_text(document_path)
        return extraction if extraction[:error]
        
        text = extraction[:text]
        
        {
          success: true,
          analysis: {
            word_count: text.split.size,
            character_count: text.length,
            paragraph_count: text.split(/\n\n+/).size,
            average_word_length: text.split.map(&:length).sum.to_f / text.split.size,
            readability_score: calculate_readability(text),
            key_topics: extract_topics(text)
          },
          metadata: extraction[:metadata]
        }
      end
      
      def query_document(document_path, query)
        return { error: "Query is required" } unless query
        
        # Extract text
        extraction = extract_text(document_path)
        return extraction if extraction[:error]
        
        # Use agent to answer query about document
        client = OpenAI::Client.new
        response = client.chat(
          parameters: {
            model: "gpt-3.5-turbo",
            messages: [
              {
                role: "system",
                content: "Answer questions about the following document content."
              },
              {
                role: "user",
                content: "Document content:\n#{extraction[:text][0..3000]}\n\nQuestion: #{query}"
              }
            ]
          }
        )
        
        {
          success: true,
          query: query,
          answer: response.dig("choices", 0, "message", "content"),
          document: File.basename(document_path)
        }
      end
      
      def calculate_readability(text)
        # Simplified Flesch Reading Ease
        sentences = text.split(/[.!?]/).size
        words = text.split.size
        syllables = text.split.map { |w| count_syllables(w) }.sum
        
        return 0 if sentences == 0 || words == 0
        
        score = 206.835 - 1.015 * (words.to_f / sentences) - 84.6 * (syllables.to_f / words)
        score.clamp(0, 100)
      end
      
      def count_syllables(word)
        # Simple syllable counting
        word.downcase.scan(/[aeiou]+/).size.clamp(1, 6)
      end
      
      def extract_topics(text)
        words = text.downcase.split(/\W+/)
        word_freq = words.tally
        word_freq.sort_by { |_, count| -count }.first(5).map(&:first)
      end
    end
    
    # Multi-modal content analyzer
    class ContentAnalyzer
      def initialize
        @vision_tool = VisionTool.new
        @audio_tool = AudioTool.new
        @document_tool = DocumentTool.new
      end
      
      def analyze_content(content_path, content_type = nil)
        # Auto-detect content type if not provided
        content_type ||= detect_content_type(content_path)
        
        case content_type
        when :image
          analyze_image_content(content_path)
        when :audio
          analyze_audio_content(content_path)
        when :video
          analyze_video_content(content_path)
        when :document
          analyze_document_content(content_path)
        else
          { error: "Unknown content type: #{content_type}" }
        end
      end
      
      private
      
      def detect_content_type(path)
        extension = File.extname(path).downcase
        
        case extension
        when ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp"
          :image
        when ".mp3", ".wav", ".m4a", ".ogg", ".flac"
          :audio
        when ".mp4", ".avi", ".mov", ".wmv", ".flv"
          :video
        when ".pdf", ".doc", ".docx", ".txt", ".html"
          :document
        else
          :unknown
        end
      end
      
      def analyze_image_content(path)
        result = @vision_tool.analyze_image(image_path: path)
        
        {
          type: :image,
          analysis: result,
          insights: extract_image_insights(result[:description])
        }
      end
      
      def analyze_audio_content(path)
        result = @audio_tool.process_audio(action: "analyze", audio_path: path)
        
        {
          type: :audio,
          analysis: result,
          insights: extract_audio_insights(result)
        }
      end
      
      def analyze_video_content(path)
        # In production, extract frames and audio
        {
          type: :video,
          analysis: {
            note: "Video analysis would extract frames and audio for processing"
          }
        }
      end
      
      def analyze_document_content(path)
        result = @document_tool.process_document(document_path: path, action: "analyze")
        
        {
          type: :document,
          analysis: result,
          insights: extract_document_insights(result[:analysis])
        }
      end
      
      def extract_image_insights(description)
        return {} unless description
        
        {
          has_people: description.include?("person") || description.include?("people"),
          has_text: description.include?("text") || description.include?("writing"),
          is_screenshot: description.include?("screenshot") || description.include?("screen"),
          primary_colors: extract_colors(description),
          detected_objects: extract_objects(description)
        }
      end
      
      def extract_audio_insights(analysis)
        return {} unless analysis[:success]
        
        {
          is_speech: analysis[:transcription].length > 10,
          sentiment: analysis[:analysis][:sentiment],
          duration_category: categorize_duration(analysis[:duration]),
          complexity: analysis[:analysis][:word_count] > 100 ? "complex" : "simple"
        }
      end
      
      def extract_document_insights(analysis)
        return {} unless analysis
        
        {
          document_type: categorize_document(analysis),
          complexity: analysis[:readability_score] < 30 ? "complex" : "simple",
          length_category: categorize_length(analysis[:word_count]),
          main_topics: analysis[:key_topics]
        }
      end
      
      def extract_colors(description)
        colors = %w[red blue green yellow black white gray brown orange purple]
        colors.select { |color| description.downcase.include?(color) }
      end
      
      def extract_objects(description)
        # Simple object extraction from description
        nouns = description.scan(/\b(?:a|an|the)\s+(\w+)\b/i).flatten
        nouns.uniq.first(5)
      end
      
      def categorize_duration(duration)
        case duration
        when 0..30 then "short"
        when 31..300 then "medium"
        else "long"
        end
      end
      
      def categorize_document(analysis)
        word_count = analysis[:word_count]
        
        case word_count
        when 0..500 then "brief"
        when 501..2000 then "article"
        when 2001..10000 then "report"
        else "book"
        end
      end
      
      def categorize_length(word_count)
        case word_count
        when 0..100 then "very_short"
        when 101..500 then "short"
        when 501..1500 then "medium"
        when 1501..5000 then "long"
        else "very_long"
        end
      end
    end
    
    # Multi-modal conversation handler
    class MultiModalConversation
      attr_reader :messages, :media_attachments
      
      def initialize
        @messages = []
        @media_attachments = {}
        @analyzer = ContentAnalyzer.new
      end
      
      def add_message(role:, content: nil, media: nil)
        message = {
          role: role,
          timestamp: Time.now
        }
        
        # Handle text content
        if content
          message[:content] = content
        end
        
        # Handle media attachments
        if media
          media_id = process_media(media)
          message[:media_id] = media_id
        end
        
        @messages << message
      end
      
      def get_conversation_context
        @messages.map do |msg|
          context = {
            role: msg[:role],
            content: msg[:content]
          }
          
          if msg[:media_id] && @media_attachments[msg[:media_id]]
            media = @media_attachments[msg[:media_id]]
            context[:media_context] = media[:analysis][:insights]
          end
          
          context
        end
      end
      
      private
      
      def process_media(media_info)
        media_id = SecureRandom.hex(8)
        
        # Analyze media
        analysis = @analyzer.analyze_content(media_info[:path], media_info[:type])
        
        @media_attachments[media_id] = {
          path: media_info[:path],
          type: media_info[:type],
          analysis: analysis,
          processed_at: Time.now
        }
        
        media_id
      end
    end
    
  end
end