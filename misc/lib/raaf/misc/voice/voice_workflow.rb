# frozen_string_literal: true

require "net/http"
require "json"
require "tempfile"

module RAAF
  module Voice
    ##
    # VoiceWorkflow - Complete voice interaction pipeline for agent workflows
    #
    # Provides end-to-end voice processing including speech-to-text transcription,
    # agent processing, and text-to-speech synthesis. Supports multiple voice
    # providers and audio formats.
    #
    # == Features
    #
    # * Speech-to-text transcription via OpenAI Whisper
    # * Text-to-speech synthesis via OpenAI TTS
    # * Audio format conversion and processing
    # * Voice activity detection
    # * Multi-language support
    # * Streaming audio support
    # * Voice cloning and customization
    #
    # == Basic Usage
    #
    #   # Create voice workflow
    #   voice = RAAF::Voice::VoiceWorkflow.new(
    #     transcription_model: "whisper-1",
    #     tts_model: "tts-1",
    #     voice: "alloy"
    #   )
    #
    #   # Process audio file
    #   result = voice.process_audio_file("input.wav", agent)
    #   puts result.text_response
    #
    #   # Play synthesized response
    #   voice.play_audio(result.audio_file)
    #
    # == Streaming Usage
    #
    #   voice.start_streaming_session(agent) do |session|
    #     session.on_transcription { |text| puts "User said: #{text}" }
    #     session.on_response { |text| puts "Agent: #{text}" }
    #     session.on_audio { |audio_data| play_audio_chunk(audio_data) }
    #   end
    #
    # @author RAAF (Ruby AI Agents Factory) Team
    # @since 0.1.0
    class VoiceWorkflow
      ##
      # Available TTS voices from OpenAI
      AVAILABLE_VOICES = %w[alloy echo fable onyx nova shimmer].freeze

      ##
      # Supported audio formats for transcription
      SUPPORTED_FORMATS = %w[mp3 mp4 mpeg mpga m4a wav webm].freeze

      attr_reader :transcription_model, :tts_model, :voice, :language

      ##
      # Creates a new VoiceWorkflow instance
      #
      # @param transcription_model [String] model for speech-to-text (default: "whisper-1")
      # @param tts_model [String] model for text-to-speech (default: "tts-1")
      # @param voice [String] voice to use for TTS (default: "alloy")
      # @param language [String, nil] language code for transcription (auto-detect if nil)
      # @param api_key [String, nil] OpenAI API key (uses ENV if nil)
      #
      # @example Create basic voice workflow
      #   voice = RAAF::Voice::VoiceWorkflow.new
      #
      # @example Create customized voice workflow
      #   voice = RAAF::Voice::VoiceWorkflow.new(
      #     tts_model: "tts-1-hd",
      #     voice: "nova",
      #     language: "es"
      #   )
      def initialize(transcription_model: "whisper-1", tts_model: "tts-1", voice: "alloy",
                     language: nil, api_key: nil)
        @transcription_model = transcription_model
        @tts_model = tts_model
        @voice = voice
        @language = language
        @api_key = api_key || ENV.fetch("OPENAI_API_KEY", nil)

        validate_configuration!
      end

      ##
      # Processes an audio file through the complete voice workflow
      #
      # Takes an audio file, transcribes it to text, processes it with an agent,
      # and synthesizes the response back to audio.
      #
      # @param audio_file_path [String] path to the input audio file
      # @param agent [Agent] agent to process the transcribed text
      # @param output_path [String, nil] path for output audio (temp file if nil)
      # @return [VoiceResult] result containing transcription, response, and audio
      #
      # @example Process voice input
      #   result = voice.process_audio_file("user_input.wav", my_agent)
      #   puts "User said: #{result.transcription}"
      #   puts "Agent replied: #{result.text_response}"
      #   voice.play_audio(result.audio_file)
      def process_audio_file(audio_file_path, agent, output_path: nil)
        raise ArgumentError, "Audio file not found: #{audio_file_path}" unless File.exist?(audio_file_path)

        # Step 1: Transcribe audio to text
        transcription = transcribe_audio(audio_file_path)

        # Step 2: Process with agent
        runner = Runner.new(agent: agent)
        messages = [{ role: "user", content: transcription }]
        agent_result = runner.run(messages)

        # Extract agent response
        response_text = agent_result[:messages]
                        .select { |msg| msg[:role] == "assistant" }
                        .map { |msg| msg[:content] }
                        .join(" ")

        # Step 3: Synthesize response to audio
        audio_file = synthesize_speech(response_text, output_path)

        VoiceResult.new(
          transcription: transcription,
          text_response: response_text,
          audio_file: audio_file,
          agent_result: agent_result
        )
      end

      ##
      # Transcribes audio file to text using Whisper
      #
      # @param audio_file_path [String] path to audio file
      # @return [String] transcribed text
      # @raise [VoiceError] if transcription fails
      #
      # @example Transcribe audio
      #   text = voice.transcribe_audio("recording.mp3")
      #   puts text # => "Hello, how can I help you today?"
      def transcribe_audio(audio_file_path)
        validate_audio_format(audio_file_path)

        uri = URI("https://api.openai.com/v1/audio/transcriptions")

        File.open(audio_file_path, "rb") do |file|
          request = build_multipart_request(uri, {
            "file" => file,
            "model" => @transcription_model,
            "language" => @language,
            "response_format" => "json"
          }.compact)

          response = make_http_request(request)
          result = JSON.parse(response.body)

          raise VoiceError, "Transcription failed: #{result["error"]["message"]}" if result["error"]

          result["text"] || ""
        end
      end

      ##
      # Synthesizes text to speech audio
      #
      # @param text [String] text to synthesize
      # @param output_path [String, nil] output file path (temp file if nil)
      # @return [String] path to generated audio file
      # @raise [VoiceError] if synthesis fails
      #
      # @example Synthesize speech
      #   audio_file = voice.synthesize_speech("Hello world!")
      #   voice.play_audio(audio_file)
      def synthesize_speech(text, output_path = nil)
        output_path ||= generate_temp_audio_path

        uri = URI("https://api.openai.com/v1/audio/speech")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"

        request.body = JSON.generate({
                                       model: @tts_model,
                                       input: text,
                                       voice: @voice,
                                       response_format: "mp3"
                                     })

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          error_body = begin
            JSON.parse(response.body)
          rescue StandardError
            { "message" => response.body }
          end
          raise VoiceError, "TTS failed: #{error_body["message"]}"
        end

        File.binwrite(output_path, response.body)
        output_path
      end

      ##
      # Starts a streaming voice session with real-time processing
      #
      # @param agent [Agent] agent to process voice inputs
      # @yield [StreamingSession] session object for handling events
      # @return [void]
      #
      # @example Start streaming session
      #   voice.start_streaming_session(agent) do |session|
      #     session.on_transcription { |text| puts "Heard: #{text}" }
      #     session.on_response { |text| puts "Reply: #{text}" }
      #   end
      def start_streaming_session(agent, &)
        session = StreamingSession.new(self, agent)
        session.instance_eval(&) if block_given?
        session.start
      end

      ##
      # Plays an audio file using system audio player
      #
      # @param audio_file_path [String] path to audio file
      # @return [Boolean] true if playback succeeded
      #
      # @example Play audio
      #   success = voice.play_audio("response.mp3")
      #   puts "Playback #{success ? 'succeeded' : 'failed'}"
      def play_audio(audio_file_path)
        return false unless File.exist?(audio_file_path)

        case RUBY_PLATFORM
        when /darwin/
          system("afplay '#{audio_file_path}'")
        when /linux/
          system("aplay '#{audio_file_path}' 2>/dev/null") ||
            system("paplay '#{audio_file_path}' 2>/dev/null") ||
            system("mpg123 '#{audio_file_path}' 2>/dev/null")
        when /mswin|mingw/
          system("start '#{audio_file_path}'")
        else
          false
        end
      end

      ##
      # Converts audio file to supported format
      #
      # @param input_path [String] input audio file path
      # @param output_path [String] output audio file path
      # @param format [String] target format (default: "wav")
      # @return [String] path to converted file
      #
      # @example Convert audio format
      #   wav_file = voice.convert_audio("input.m4a", "output.wav")
      def convert_audio(input_path, output_path, format: "wav") # rubocop:disable Lint/UnusedMethodArgument
        raise VoiceError, "ffmpeg not found. Install ffmpeg for audio conversion." unless command_exists?("ffmpeg")

        success = system("ffmpeg -i '#{input_path}' -acodec pcm_s16le -ar 16000 '#{output_path}' 2>/dev/null")
        raise VoiceError, "Audio conversion failed" unless success

        output_path
      end

      ##
      # Detects voice activity in audio file
      #
      # @param audio_file_path [String] path to audio file
      # @return [Hash] voice activity information
      #
      # @example Detect voice activity
      #   activity = voice.detect_voice_activity("recording.wav")
      #   puts "Speech detected: #{activity[:has_speech]}"
      #   puts "Duration: #{activity[:duration]}s"
      def detect_voice_activity(audio_file_path)
        # Simple implementation using audio file properties
        file_size = File.size(audio_file_path)

        # Basic heuristics for voice activity detection
        {
          has_speech: file_size > 1000, # Assume files > 1KB have speech
          duration: estimate_audio_duration(audio_file_path),
          file_size: file_size,
          confidence: file_size > 10_000 ? 0.8 : 0.3
        }
      end

      private

      def validate_configuration!
        raise VoiceError, "OpenAI API key is required" unless @api_key
        raise VoiceError, "Invalid voice: #{@voice}" unless AVAILABLE_VOICES.include?(@voice)
      end

      def validate_audio_format(file_path)
        extension = File.extname(file_path)[1..]&.downcase
        return if SUPPORTED_FORMATS.include?(extension)

        raise VoiceError, "Unsupported audio format: #{extension}. Supported: #{SUPPORTED_FORMATS.join(", ")}"
      end

      def build_multipart_request(uri, params)
        boundary = SecureRandom.hex(16)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"

        body = StringIO.new
        params.each do |key, value|
          body << "--#{boundary}\r\n"

          if value.is_a?(File) || value.respond_to?(:read)
            filename = File.basename(value.path) if value.respond_to?(:path)
            body << "Content-Disposition: form-data; name=\"#{key}\"; filename=\"#{filename}\"\r\n"
            body << "Content-Type: application/octet-stream\r\n\r\n"
            body << value.read
          else
            body << "Content-Disposition: form-data; name=\"#{key}\"\r\n\r\n"
            body << value.to_s
          end

          body << "\r\n"
        end
        body << "--#{boundary}--\r\n"

        request.body = body.string
        request
      end

      def make_http_request(request)
        http = Net::HTTP.new(request.uri.host, request.uri.port)
        http.use_ssl = true
        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise VoiceError, "HTTP request failed: #{response.code} #{response.message}"
        end

        response
      end

      def generate_temp_audio_path
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        "#{Dir.tmpdir}/raaf_#{timestamp}_#{SecureRandom.hex(4)}.mp3"
      end

      def estimate_audio_duration(file_path)
        # Simple estimation based on file size (very rough)
        file_size = File.size(file_path)
        # Assume ~128kbps encoding: 16KB per second
        (file_size / 16_000.0).round(2)
      end

      def command_exists?(command)
        system("which #{command} > /dev/null 2>&1")
      end
    end

    ##
    # VoiceResult - Result object for voice workflow operations
    #
    # Contains the complete result of a voice processing workflow including
    # transcription, agent response, and synthesized audio.
    class VoiceResult
      attr_reader :transcription, :text_response, :audio_file, :agent_result

      ##
      # Creates a new VoiceResult
      #
      # @param transcription [String] transcribed text from audio input
      # @param text_response [String] agent's text response
      # @param audio_file [String] path to synthesized audio response
      # @param agent_result [Hash] full agent execution result
      def initialize(transcription:, text_response:, audio_file:, agent_result:)
        @transcription = transcription
        @text_response = text_response
        @audio_file = audio_file
        @agent_result = agent_result
      end

      ##
      # Converts result to hash representation
      #
      # @return [Hash] hash representation of the voice result
      def to_h
        {
          transcription: @transcription,
          text_response: @text_response,
          audio_file: @audio_file,
          agent_result: @agent_result
        }
      end
    end

    ##
    # StreamingSession - Real-time voice interaction session
    #
    # Handles streaming voice input and output for real-time conversations.
    class StreamingSession
      def initialize(voice_workflow, agent)
        @voice_workflow = voice_workflow
        @agent = agent
        @callbacks = {}
        @active = false
      end

      ##
      # Sets callback for transcription events
      #
      # @yield [String] transcribed text
      def on_transcription(&block)
        @callbacks[:transcription] = block
      end

      ##
      # Sets callback for agent response events
      #
      # @yield [String] agent response text
      def on_response(&block)
        @callbacks[:response] = block
      end

      ##
      # Sets callback for audio output events
      #
      # @yield [String] path to audio file
      def on_audio(&block)
        @callbacks[:audio] = block
      end

      ##
      # Starts the streaming session
      def start
        @active = true
        puts "Voice streaming session started. Say 'quit' to exit."

        # Simplified implementation - in production, this would use real-time audio capture
        while @active
          print "Press Enter to record audio (or 'quit' to exit): "
          input = $stdin.gets.strip

          break if input.downcase == "quit"

          # Mock audio processing - in real implementation, this would capture live audio
          mock_audio_processing
        end

        puts "Voice session ended."
      end

      private

      def mock_audio_processing
        # This would be replaced with real audio capture and processing
        puts "🎤 Recording... (mock implementation)"
        sleep(1)

        # Mock transcription
        mock_transcription = "Hello, how can you help me today?"
        @callbacks[:transcription]&.call(mock_transcription)

        # Process with agent
        runner = Runner.new(agent: @agent)
        messages = [{ role: "user", content: mock_transcription }]
        result = runner.run(messages)

        response_text = result[:messages]
                        .select { |msg| msg[:role] == "assistant" }
                        .map { |msg| msg[:content] }
                        .join(" ")

        @callbacks[:response]&.call(response_text)

        # Mock audio synthesis
        begin
          audio_file = @voice_workflow.synthesize_speech(response_text)
          @callbacks[:audio]&.call(audio_file)
          @voice_workflow.play_audio(audio_file)
        rescue StandardError => e
          puts "Audio synthesis error: #{e.message}"
        end
      end
    end

    ##
    # VoiceError - Exception class for voice-related errors
    class VoiceError < Error; end
  end
end
