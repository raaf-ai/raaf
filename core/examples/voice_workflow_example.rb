#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates voice workflow capabilities for multi-modal AI interactions.
# Voice workflows enable natural spoken conversations with AI agents, combining
# speech-to-text, agent processing, and text-to-speech for seamless voice experiences.
# This is particularly valuable for accessibility, hands-free applications, and
# natural user interfaces.

require_relative "../lib/raaf-core"

# ============================================================================
# VOICE WORKFLOW SETUP AND CONFIGURATION
# ============================================================================

puts "=== Voice Workflow and Multi-Modal AI Example ==="
puts "=" * 60

# Environment validation
unless ENV["OPENAI_API_KEY"]
  puts "NOTE: OPENAI_API_KEY not set. Running in demo mode."
  puts "For live voice processing, set your API key."
  puts "Get your API key from: https://platform.openai.com/api-keys"
  puts
end

# Check for audio file dependencies
SAMPLE_AUDIO_DIR = "#{__dir__}/sample_audio".freeze
unless Dir.exist?(SAMPLE_AUDIO_DIR)
  puts "📁 Creating sample audio directory: #{SAMPLE_AUDIO_DIR}"
  Dir.mkdir(SAMPLE_AUDIO_DIR)
end

puts "✅ Voice workflow environment ready"

# ============================================================================
# VOICE WORKFLOW TOOLS AND UTILITIES
# ============================================================================

# Simulates speech-to-text conversion for demonstration.
# In production, this would integrate with OpenAI's Whisper API or similar services.
#
# The audio_file parameter would be a path to an actual audio file.
def speech_to_text(audio_file:, language: "en", temperature: 0.0)
  puts "🎤 Processing speech-to-text for: #{audio_file}"
  puts "   Language: #{language}, Temperature: #{temperature}"

  begin
    # In demo mode, simulate different types of audio input
    transcribed_text = case File.basename(audio_file, ".*")
                       when /question/
                         "What are the benefits of artificial intelligence in healthcare?"
                       when /command/
                         "Please schedule a meeting for tomorrow at 2 PM"
                       when /conversation/
                         "Hello, I need help understanding machine learning concepts"
                       when /technical/
                         "Explain the difference between supervised and unsupervised learning"
                       else
                         # Default response for any audio file
                         "Hello, how can you help me today?"
                       end

    # Simulate processing time
    sleep(0.5)

    puts "   ✅ Transcription complete: \"#{transcribed_text}\""

    {
      success: true,
      text: transcribed_text,
      language: language,
      duration: 2.3, # Simulated audio duration
      confidence: 0.95
    }
  rescue StandardError => e
    puts "   ❌ Speech-to-text failed: #{e.message}"
    {
      success: false,
      error: e.message,
      text: nil
    }
  end
end

# Simulates text-to-speech conversion for demonstration.
# In production, this would integrate with OpenAI's TTS API or similar services.
#
# The voice parameter controls the speech characteristics and personality.
def text_to_speech(text:, voice: "alloy", speed: 1.0, output_file: nil)
  puts "🔊 Converting text to speech:"
  puts "   Text: \"#{text[0..80]}#{"..." if text.length > 80}\""
  puts "   Voice: #{voice}, Speed: #{speed}"

  begin
    # Validate voice options
    available_voices = %w[alloy echo fable onyx nova shimmer]
    unless available_voices.include?(voice)
      puts "   ⚠️  Voice '#{voice}' not available, using 'alloy'"
      voice = "alloy"
    end

    # Generate output filename if not provided
    output_file ||= "#{SAMPLE_AUDIO_DIR}/tts_output_#{Time.now.to_i}.mp3"

    # Simulate processing time based on text length
    processing_time = [text.length / 100.0, 0.5].max
    sleep(processing_time)

    # Simulate file creation
    File.write(output_file, "# Simulated audio file content for: #{text[0..50]}")

    puts "   ✅ Text-to-speech complete: #{output_file}"

    {
      success: true,
      audio_file: output_file,
      voice: voice,
      duration: text.length / 10.0,  # Estimated speech duration
      file_size: text.length * 100   # Estimated file size in bytes
    }
  rescue StandardError => e
    puts "   ❌ Text-to-speech failed: #{e.message}"
    {
      success: false,
      error: e.message,
      audio_file: nil
    }
  end
end

# Voice activity detection for real-time applications.
# Detects when the user starts and stops speaking.
def detect_voice_activity(audio_stream:, threshold: 0.5, timeout: 3.0)
  puts "🎵 Detecting voice activity..."
  puts "   Threshold: #{threshold}, Timeout: #{timeout}s"

  # Simulate voice activity detection
  sleep(0.2)

  # Simulated detection result
  activity_detected = rand > 0.3 # 70% chance of detecting voice

  if activity_detected
    puts "   ✅ Voice activity detected"
    {
      detected: true,
      start_time: Time.now - 1.2,
      confidence: 0.8,
      energy_level: 0.65
    }
  else
    puts "   ❌ No voice activity detected"
    {
      detected: false,
      reason: "Audio level below threshold"
    }
  end
end

puts "✅ Voice processing tools loaded"

# ============================================================================
# VOICE-ENABLED AGENT SETUP
# ============================================================================

puts "\n=== Voice-Enabled Agent Configuration ==="
puts "-" * 50

# Create an agent optimized for voice interactions.
# Voice conversations require clear, concise responses and natural language flow.
voice_agent = RAAF::Agent.new(
  # Clear identification for voice interactions
  name: "VoiceAssistant",

  # Instructions optimized for spoken responses
  instructions: "You are a helpful voice assistant. Provide clear, concise responses " \
                "suitable for spoken conversation. Use natural language and avoid complex " \
                "formatting. Keep responses under 200 words unless specifically asked for " \
                "detailed explanations. Be conversational and friendly.",

  # gpt-4o provides excellent voice-optimized responses
  model: "gpt-4o"
)

# Add voice-specific tools
voice_agent.add_tool(method(:speech_to_text))
voice_agent.add_tool(method(:text_to_speech))
voice_agent.add_tool(method(:detect_voice_activity))

puts "✅ Voice-enabled agent created with voice processing tools"
puts "   Model: #{voice_agent.model}"
puts "   Voice tools: #{voice_agent.tools.map(&:name).join(", ")}"

# ============================================================================
# BASIC VOICE WORKFLOW
# ============================================================================

puts "\n=== Basic Voice Interaction Workflow ==="
puts "-" * 50

# Create runner for voice interactions
voice_runner = RAAF::Runner.new(agent: voice_agent)

# Simulate a complete voice interaction cycle
def voice_interaction_cycle(runner, audio_input_file, voice_style = "alloy")
  puts "🔄 Starting voice interaction cycle..."
  puts "   Input audio: #{audio_input_file}"
  puts "   Voice style: #{voice_style}"

  begin
    # Step 1: Speech-to-Text
    puts "\n1️⃣ Speech-to-Text Processing:"
    transcription = speech_to_text(audio_file: audio_input_file, language: "en")

    unless transcription[:success]
      puts "❌ Voice interaction failed at speech-to-text stage"
      return { success: false, stage: "speech_to_text", error: transcription[:error] }
    end

    user_text = transcription[:text]
    puts "   User said: \"#{user_text}\""

    # Step 2: Agent Processing
    puts "\n2️⃣ Agent Processing:"
    start_time = Time.now

    result = runner.run(user_text)
    processing_time = Time.now - start_time

    agent_response = result.final_output
    puts "   Agent response: \"#{agent_response[0..100]}#{"..." if agent_response.length > 100}\""
    puts "   Processing time: #{(processing_time * 1000).round(1)}ms"

    # Step 3: Text-to-Speech
    puts "\n3️⃣ Text-to-Speech Generation:"
    tts_result = text_to_speech(
      text: agent_response,
      voice: voice_style,
      speed: 1.0
    )

    unless tts_result[:success]
      puts "❌ Voice interaction failed at text-to-speech stage"
      return { success: false, stage: "text_to_speech", error: tts_result[:error] }
    end

    puts "   Audio file created: #{tts_result[:audio_file]}"
    puts "   Estimated duration: #{tts_result[:duration].round(1)}s"

    # Complete interaction summary
    total_time = processing_time + 0.5 + (tts_result[:duration] / 10) # Estimated total

    {
      success: true,
      user_input: user_text,
      agent_response: agent_response,
      audio_output: tts_result[:audio_file],
      total_duration: total_time,
      transcription_confidence: transcription[:confidence],
      processing_time: processing_time
    }
  rescue StandardError => e
    puts "❌ Voice interaction cycle failed: #{e.message}"
    { success: false, stage: "unknown", error: e.message }
  end
end

# Test basic voice interaction
puts "Testing basic voice interaction:"

# Simulate different types of voice inputs
test_audio_files = [
  "#{SAMPLE_AUDIO_DIR}/question_healthcare.wav",
  "#{SAMPLE_AUDIO_DIR}/command_schedule.wav",
  "#{SAMPLE_AUDIO_DIR}/conversation_greeting.wav"
]

# Create sample files for demonstration
test_audio_files.each do |file|
  File.write(file, "# Sample audio file: #{File.basename(file)}")
end

begin
  # Test voice interaction
  interaction_result = voice_interaction_cycle(
    voice_runner,
    test_audio_files.first,
    "nova" # Use nova voice for friendly tone
  )

  if interaction_result[:success]
    puts "\n✅ Voice interaction successful!"
    puts "   Total duration: #{interaction_result[:total_duration].round(2)}s"
    puts "   Confidence: #{(interaction_result[:transcription_confidence] * 100).round(1)}%"
  else
    puts "\n❌ Voice interaction failed at #{interaction_result[:stage]} stage"
  end
rescue RAAF::Error => e
  puts "\n❌ Voice interaction failed: #{e.message}"
  puts "\n=== Demo Mode Voice Workflow ==="
  puts "1️⃣ Speech-to-Text: 'What are the benefits of AI in healthcare?'"
  puts "2️⃣ Agent Processing: 'AI in healthcare improves diagnostics, enables personalized treatment...'"
  puts "3️⃣ Text-to-Speech: Generated audio response with natural voice"
  puts "✅ Complete voice interaction cycle demonstrated"
end

# ============================================================================
# MULTI-TURN VOICE CONVERSATION
# ============================================================================

puts "\n=== Multi-Turn Voice Conversation ==="
puts "-" * 50

# Voice conversation manager for maintaining context
class VoiceConversationManager

  def initialize(agent, runner, default_voice: "alloy")
    @agent = agent
    @runner = runner
    @default_voice = default_voice
    @conversation_history = []
    @context_memory = {}
  end

  def process_voice_turn(audio_file, voice_style: nil, context: {})
    voice_style ||= @default_voice
    turn_number = @conversation_history.length + 1

    puts "🗣️  Turn #{turn_number}: Processing voice input"

    # Update context memory
    @context_memory.merge!(context)

    # Speech-to-text
    transcription = speech_to_text(audio_file: audio_file)
    return build_error_result("Speech recognition failed", transcription) unless transcription[:success]

    user_input = transcription[:text]

    # Add context to the user input if available
    enhanced_input = user_input
    if @context_memory.any?
      context_info = @context_memory.map { |k, v| "#{k}: #{v}" }.join(", ")
      enhanced_input = "#{user_input} [Context: #{context_info}]"
    end

    # Agent processing
    start_time = Time.now
    result = @runner.run(enhanced_input)
    processing_time = Time.now - start_time

    agent_response = result.final_output

    # Text-to-speech
    tts_result = text_to_speech(text: agent_response, voice: voice_style)
    return build_error_result("Speech synthesis failed", tts_result) unless tts_result[:success]

    # Store conversation turn
    turn_data = {
      turn: turn_number,
      timestamp: Time.now,
      user_input: user_input,
      agent_response: agent_response,
      audio_output: tts_result[:audio_file],
      voice_style: voice_style,
      processing_time: processing_time,
      context: @context_memory.dup
    }

    @conversation_history << turn_data

    puts "   ✅ Turn #{turn_number} complete"
    puts "   User: \"#{user_input}\""
    puts "   Agent: \"#{agent_response[0..80]}#{"..." if agent_response.length > 80}\""

    turn_data
  end

  def conversation_summary
    return { turns: 0, total_duration: 0 } if @conversation_history.empty?

    total_duration = @conversation_history.sum { |turn| turn[:processing_time] }

    {
      turns: @conversation_history.length,
      total_duration: total_duration,
      average_response_time: total_duration / @conversation_history.length,
      voice_styles_used: @conversation_history.map { |t| t[:voice_style] }.uniq,
      conversation_start: @conversation_history.first[:timestamp],
      conversation_end: @conversation_history.last[:timestamp]
    }
  end

  private

  def build_error_result(message, failed_result)
    {
      success: false,
      error: message,
      details: failed_result[:error] || "Unknown error"
    }
  end

end

# Demonstrate multi-turn conversation
puts "Testing multi-turn voice conversation:"

conversation_manager = VoiceConversationManager.new(
  voice_agent,
  voice_runner,
  default_voice: "echo" # Use echo voice for technical discussions
)

# Simulate a multi-turn conversation about AI
conversation_turns = [
  {
    audio: "#{SAMPLE_AUDIO_DIR}/turn1_greeting.wav",
    context: { topic: "AI introduction", user_level: "beginner" }
  },
  {
    audio: "#{SAMPLE_AUDIO_DIR}/turn2_technical.wav",
    context: { topic: "machine learning", user_level: "intermediate" }
  },
  {
    audio: "#{SAMPLE_AUDIO_DIR}/turn3_application.wav",
    context: { topic: "AI applications", user_level: "advanced" }
  }
]

# Create audio files for demo
conversation_turns.each_with_index do |turn, index|
  File.write(turn[:audio], "# Sample audio for turn #{index + 1}")
end

begin
  conversation_turns.each_with_index do |turn, index|
    voice_style = %w[alloy nova shimmer][index % 3] # Vary voice styles

    result = conversation_manager.process_voice_turn(
      turn[:audio],
      voice_style: voice_style,
      context: turn[:context]
    )

    unless result[:success]
      puts "❌ Turn failed: #{result[:error]}"
      break
    end

    # Small delay between turns
    sleep(0.1)
  end

  # Conversation summary
  summary = conversation_manager.conversation_summary
  puts "\n📊 Conversation Summary:"
  puts "   Total turns: #{summary[:turns]}"
  puts "   Total duration: #{summary[:total_duration].round(2)}s"
  puts "   Average response time: #{summary[:average_response_time].round(3)}s"
  puts "   Voice styles used: #{summary[:voice_styles_used].join(", ")}"
rescue RAAF::Error => e
  puts "❌ Multi-turn conversation failed: #{e.message}"
  puts "\n=== Demo Mode Multi-Turn Conversation ==="
  puts "Turn 1: 'Hello, tell me about AI' → 'AI is a technology that enables machines to simulate human intelligence...'"
  puts "Turn 2: 'How does machine learning work?' → 'Machine learning uses algorithms to find patterns in data...'"
  puts "Turn 3: 'What are real-world applications?' → 'AI is used in healthcare, finance, transportation...'"
  puts "✅ Multi-turn voice conversation demonstrated"
end

# ============================================================================
# REAL-TIME VOICE PROCESSING
# ============================================================================

puts "\n=== Real-Time Voice Processing Simulation ==="
puts "-" * 50

# Simulate real-time voice processing with streaming
class RealTimeVoiceProcessor

  def initialize(agent, runner)
    @agent = agent
    @runner = runner
    @is_listening = false
    @voice_buffer = []
  end

  def start_listening
    @is_listening = true
    puts "🎤 Real-time voice processing started..."
    puts "   Monitoring for voice activity..."

    # Simulate real-time processing loop
    simulate_real_time_processing
  end

  def stop_listening
    @is_listening = false
    puts "⏹️  Real-time voice processing stopped"
  end

  private

  def simulate_real_time_processing
    audio_chunks = 0

    while @is_listening && audio_chunks < 5 # Limit for demo
      # Simulate voice activity detection
      activity = detect_voice_activity(
        audio_stream: "live_stream",
        threshold: 0.4,
        timeout: 2.0
      )

      if activity[:detected]
        puts "   🔊 Voice detected, processing chunk #{audio_chunks + 1}..."

        # Simulate processing audio chunk
        process_audio_chunk("chunk_#{audio_chunks + 1}")
        audio_chunks += 1
      else
        puts "   🔇 Listening for voice..."
      end

      sleep(0.5) # Simulate real-time interval
    end

    stop_listening
  end

  def process_audio_chunk(chunk_id)
    # Simulate streaming speech recognition and processing
    puts "     Processing audio chunk: #{chunk_id}"

    # Simulate partial transcription
    partial_text = ["Hello", "Hello there", "Hello there, how", "Hello there, how are you?"][rand(4)]
    puts "     Partial transcript: \"#{partial_text}\""

    # If we have a complete phrase, process it
    return unless partial_text.end_with?("?") || partial_text.length > 15

    puts "     Complete phrase detected, processing with agent..."

    # Quick agent response for real-time feel
    response = "I'm doing well, thank you for asking!"
    puts "     Agent response: \"#{response}\""

    # Trigger TTS for immediate feedback
    tts_result = text_to_speech(text: response, voice: "alloy", speed: 1.2)
    puts "     Audio response ready: #{tts_result[:audio_file]}" if tts_result[:success]
  end

end

# Demonstrate real-time processing
puts "Testing real-time voice processing:"

real_time_processor = RealTimeVoiceProcessor.new(voice_agent, voice_runner)

begin
  # Start real-time processing (will run for demo duration)
  real_time_processor.start_listening

  puts "✅ Real-time voice processing demonstration complete"
rescue StandardError => e
  puts "❌ Real-time processing failed: #{e.message}"
  puts "\n=== Demo Mode Real-Time Processing ==="
  puts "🎤 Listening for voice activity..."
  puts "🔊 Voice detected, processing..."
  puts "📝 Transcribing: 'Hello there, how are you?'"
  puts "🤖 Agent response: 'I'm doing well, thank you!'"
  puts "🔊 Playing audio response..."
  puts "✅ Real-time voice interaction complete"
end

# ============================================================================
# VOICE WORKFLOW BEST PRACTICES
# ============================================================================

puts "\n=== Voice Workflow Best Practices ==="
puts "-" * 50

puts "✅ Speech Recognition Optimization:"
puts "   • Use appropriate audio quality (16kHz+ sample rate)"
puts "   • Implement noise reduction and filtering"
puts "   • Handle multiple languages and accents"
puts "   • Provide fallback for recognition failures"
puts "   • Use confidence thresholds for accuracy"

puts "\n✅ Agent Response Optimization:"
puts "   • Keep responses concise for spoken format"
puts "   • Use natural conversational language"
puts "   • Avoid complex formatting or lists"
puts "   • Implement context awareness for flow"
puts "   • Handle interruptions gracefully"

puts "\n✅ Text-to-Speech Optimization:"
puts "   • Choose appropriate voice characteristics"
puts "   • Adjust speech rate for comprehension"
puts "   • Use SSML for better pronunciation"
puts "   • Implement emotional tone matching"
puts "   • Cache frequently used phrases"

puts "\n✅ Real-Time Considerations:"
puts "   • Minimize latency in the processing pipeline"
puts "   • Implement streaming for immediate feedback"
puts "   • Use voice activity detection efficiently"
puts "   • Handle network interruptions gracefully"
puts "   • Provide visual feedback during processing"

puts "\n✅ User Experience Design:"
puts "   • Clear indication of listening states"
puts "   • Timeout handling for silent periods"
puts "   • Error recovery and retry mechanisms"
puts "   • Accessibility considerations"
puts "   • Multi-modal fallback options"

# ============================================================================
# PRODUCTION VOICE INTEGRATION
# ============================================================================

puts "\n=== Production Voice Integration Pattern ==="
puts "-" * 50

# Example production voice service class
class ProductionVoiceService

  def initialize(agent, configuration = {})
    @agent = agent
    @config = default_configuration.merge(configuration)
    @session_manager = VoiceSessionManager.new
  end

  def start_voice_session(user_id:, preferences: {})
    session = @session_manager.create_session(user_id, preferences)

    puts "🎤 Voice session started for user: #{user_id}"
    puts "   Session ID: #{session[:id]}"
    puts "   Voice preferences: #{preferences}"

    session
  end

  def process_voice_input(session_id:, audio_data:, context: {})
    session = @session_manager.get_session(session_id)
    return { error: "Session not found" } unless session

    # Production voice processing pipeline
    pipeline_result = {
      session_id: session_id,
      timestamp: Time.now,
      stages: {}
    }

    # Stage 1: Speech Recognition
    transcription = advanced_speech_recognition(audio_data, session[:preferences])
    pipeline_result[:stages][:transcription] = transcription

    return pipeline_result unless transcription[:success]

    # Stage 2: Intent Recognition and Context
    enhanced_input = enhance_with_context(transcription[:text], session, context)
    pipeline_result[:stages][:context_enhancement] = { text: enhanced_input }

    # Stage 3: Agent Processing
    agent_response = process_with_agent(enhanced_input)
    pipeline_result[:stages][:agent_processing] = agent_response

    # Stage 4: Response Optimization
    optimized_response = optimize_for_speech(agent_response[:text])
    pipeline_result[:stages][:response_optimization] = { optimized_text: optimized_response }

    # Stage 5: Speech Synthesis
    audio_response = advanced_speech_synthesis(optimized_response, session[:preferences])
    pipeline_result[:stages][:speech_synthesis] = audio_response

    # Update session history
    @session_manager.update_session(session_id, {
                                      user_input: transcription[:text],
                                      agent_response: optimized_response,
                                      timestamp: Time.now
                                    })

    pipeline_result[:success] = true
    pipeline_result[:final_audio] = audio_response[:audio_url]
    pipeline_result
  end

  private

  def default_configuration
    {
      speech_recognition: {
        model: "whisper-1",
        language: "auto-detect",
        temperature: 0.0
      },
      speech_synthesis: {
        voice: "alloy",
        speed: 1.0,
        format: "mp3"
      },
      agent_processing: {
        max_response_length: 200,
        conversation_style: "natural"
      }
    }
  end

  def advanced_speech_recognition(_audio_data, _preferences)
    # Simulate advanced speech recognition with preferences
    { success: true, text: "Simulated transcription", confidence: 0.95 }
  end

  def enhance_with_context(text, _session, _context)
    "#{text} [Session context and user preferences applied]"
  end

  def process_with_agent(enhanced_input)
    { success: true, text: "Simulated agent response to: #{enhanced_input}" }
  end

  def optimize_for_speech(text)
    # Optimize text for spoken delivery
    text.gsub(/[^\w\s.,!?]/, "").squeeze(" ")
  end

  def advanced_speech_synthesis(_text, _preferences)
    { success: true, audio_url: "https://example.com/audio/response.mp3" }
  end

end

# Voice session management
class VoiceSessionManager

  def initialize
    @sessions = {}
  end

  def create_session(user_id, preferences)
    session_id = "voice_#{Time.now.to_i}_#{rand(1000)}"

    @sessions[session_id] = {
      id: session_id,
      user_id: user_id,
      preferences: preferences,
      created_at: Time.now,
      history: []
    }
  end

  def get_session(session_id)
    @sessions[session_id]
  end

  def update_session(session_id, interaction_data)
    return unless @sessions[session_id]

    @sessions[session_id][:history] << interaction_data
  end

end

# Demonstrate production voice service
puts "Testing production voice service integration:"

production_service = ProductionVoiceService.new(voice_agent)

# Create voice session
session = production_service.start_voice_session(
  user_id: "user_123",
  preferences: { voice: "nova", language: "en", speed: 1.1 }
)

# Process voice input
result = production_service.process_voice_input(
  session_id: session[:id],
  audio_data: "simulated_audio_data",
  context: { location: "office", device: "mobile" }
)

puts "✅ Production voice processing pipeline:"
result[:stages].each do |stage, data|
  puts "   #{stage}: #{data[:success] ? "✅" : "❌"}"
end

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Voice Workflow Example Complete! ==="
puts "\nKey Features Demonstrated:"
puts "• Complete voice interaction pipeline (STT → Agent → TTS)"
puts "• Multi-turn voice conversations with context"
puts "• Real-time voice processing simulation"
puts "• Production-ready voice service architecture"
puts "• Voice activity detection and stream processing"

puts "\nVoice Workflow Components:"
puts "• Speech-to-Text with confidence scoring"
puts "• Context-aware agent processing"
puts "• Natural language optimization for speech"
puts "• Text-to-Speech with voice customization"
puts "• Session management and conversation history"

puts "\nProduction Considerations:"
puts "• Implement proper audio quality standards"
puts "• Use streaming for real-time responsiveness"
puts "• Handle network latency and interruptions"
puts "• Provide accessibility and fallback options"
puts "• Monitor voice interaction metrics and quality"

# Cleanup demo files
Dir.glob("#{SAMPLE_AUDIO_DIR}/*").each { |f| File.delete(f) if File.file?(f) }
puts "\n🧹 Demo files cleaned up"
