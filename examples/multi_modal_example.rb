#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"
require_relative "../lib/openai_agents/multi_modal"

# Set API key from environment
OpenAI.configure do |config|
  config.access_token = ENV.fetch("OPENAI_API_KEY", nil)
end

puts "=== Multi-Modal Agent Support Example ==="
puts

# Example 1: Multi-Modal Agent Creation
puts "Example 1: Multi-Modal Agent Creation"
puts "-" * 50

# Create a multi-modal agent
multi_modal_agent = OpenAIAgents::MultiModal::MultiModalAgent.new(
  name: "VisionAudioExpert",
  model: "gpt-4-vision-preview",
  instructions: "You are a multi-modal AI assistant capable of analyzing images, audio, and documents. Use the appropriate tools to process different media types."
)

puts "Created multi-modal agent: #{multi_modal_agent.name}"
puts "Available tools:"
multi_modal_agent.tools.each do |tool|
  puts "  - #{tool.name}: #{tool.description}"
end
puts

# Example 2: Vision Tool
puts "Example 2: Vision Tool - Image Analysis"
puts "-" * 50

vision_tool = OpenAIAgents::MultiModal::VisionTool.new

# Analyze a local image (mock example)
puts "Analyzing local image..."
puts "Note: In real usage, provide an actual image path"
mock_vision_result = {
  success: true,
  description: "The image shows a modern office workspace with a laptop displaying code, a coffee mug, and some technical books on the desk. Natural lighting comes from a window on the left.",
  metadata: {
    source: "/path/to/workspace.jpg",
    analyzed_at: Time.now.iso8601
  }
}

puts "Vision analysis result:"
puts "  Description: #{mock_vision_result[:description]}"
puts "  Analyzed at: #{mock_vision_result[:metadata][:analyzed_at]}"
puts

# Analyze with specific question
puts "\nAnalyzing image with specific question..."
question = "What programming language is shown on the laptop screen?"
mock_question_result = {
  success: true,
  description: "Looking at the laptop screen, I can see code that appears to be Ruby. There are familiar Ruby syntax elements like 'def', 'end' keywords, and the distinctive Ruby method calling style.",
  metadata: {
    source: "/path/to/workspace.jpg",
    analyzed_at: Time.now.iso8601
  }
}

puts "Question: #{question}"
puts "Answer: #{mock_question_result[:description]}"
puts

# Example 3: Audio Tool
puts "Example 3: Audio Tool - Speech Processing"
puts "-" * 50

audio_tool = OpenAIAgents::MultiModal::AudioTool.new

# Transcribe audio (mock example)
puts "Transcribing audio file..."
mock_transcription = {
  success: true,
  text: "Hello, this is a test of the audio transcription system. The OpenAI Agents Ruby gem now supports multi-modal capabilities including vision, audio, and document processing.",
  language: "en",
  duration: 8.5
}

puts "Transcription result:"
puts "  Text: \"#{mock_transcription[:text]}\""
puts "  Duration: #{mock_transcription[:duration]}s"
puts "  Language: #{mock_transcription[:language]}"
puts

# Generate speech (mock example)
puts "\nGenerating speech from text..."
text_to_speak = "Welcome to the multi-modal agent demonstration."
mock_speech_result = {
  success: true,
  audio_path: "/tmp/speech_output.mp3",
  text_length: text_to_speak.length,
  voice: "alloy"
}

puts "Text: \"#{text_to_speak}\""
puts "Generated audio:"
puts "  File: #{mock_speech_result[:audio_path]}"
puts "  Voice: #{mock_speech_result[:voice]}"
puts

# Analyze audio (mock example)
puts "\nAnalyzing audio content..."
mock_audio_analysis = {
  success: true,
  transcription: "This audio contains a technical presentation about AI agents.",
  analysis: {
    word_count: 12,
    sentiment: "positive",
    key_topics: %w[audio technical presentation AI agents],
    language_confidence: 0.95
  },
  duration: 15.3
}

puts "Audio analysis:"
puts "  Duration: #{mock_audio_analysis[:duration]}s"
puts "  Word count: #{mock_audio_analysis[:analysis][:word_count]}"
puts "  Sentiment: #{mock_audio_analysis[:analysis][:sentiment]}"
puts "  Key topics: #{mock_audio_analysis[:analysis][:key_topics].join(', ')}"
puts

# Example 4: Document Tool
puts "Example 4: Document Tool - Document Processing"
puts "-" * 50

document_tool = OpenAIAgents::MultiModal::DocumentTool.new

# Extract text from document (mock example)
puts "Extracting text from PDF document..."
mock_extraction = {
  success: true,
  text: "OpenAI Agents Ruby Documentation\n\nChapter 1: Introduction\nThe OpenAI Agents Ruby gem provides a comprehensive framework for building AI-powered applications...",
  metadata: {
    filename: "openai_agents_guide.pdf",
    size: 156_789,
    type: ".pdf",
    extracted_at: Time.now.iso8601
  }
}

puts "Extraction result:"
puts "  Filename: #{mock_extraction[:metadata][:filename]}"
puts "  Size: #{mock_extraction[:metadata][:size]} bytes"
puts "  Preview: #{mock_extraction[:text][0..100]}..."
puts

# Analyze document (mock example)
puts "\nAnalyzing document structure..."
mock_doc_analysis = {
  success: true,
  analysis: {
    word_count: 5432,
    character_count: 32_456,
    paragraph_count: 87,
    average_word_length: 5.8,
    readability_score: 65.3,
    key_topics: %w[agents ruby framework AI development]
  }
}

puts "Document analysis:"
puts "  Word count: #{mock_doc_analysis[:analysis][:word_count]}"
puts "  Paragraphs: #{mock_doc_analysis[:analysis][:paragraph_count]}"
puts "  Readability: #{mock_doc_analysis[:analysis][:readability_score]}/100"
puts "  Key topics: #{mock_doc_analysis[:analysis][:key_topics].join(', ')}"
puts

# Query document (mock example)
puts "\nQuerying document content..."
query = "What are the main features of the OpenAI Agents Ruby gem?"
mock_query_result = {
  success: true,
  query: query,
  answer: "The main features include: 1) Multi-agent support with handoffs, 2) Built-in tools for various tasks, 3) Comprehensive tracing and monitoring, 4) Multi-modal capabilities for vision, audio, and documents, 5) Workflow orchestration engine.",
  document: "openai_agents_guide.pdf"
}

puts "Query: #{query}"
puts "Answer: #{mock_query_result[:answer]}"
puts

# Example 5: Content Analyzer
puts "Example 5: Unified Content Analyzer"
puts "-" * 50

analyzer = OpenAIAgents::MultiModal::ContentAnalyzer.new

# Analyze different content types
content_types = [
  { path: "/path/to/photo.jpg", expected_type: :image },
  { path: "/path/to/podcast.mp3", expected_type: :audio },
  { path: "/path/to/report.pdf", expected_type: :document }
]

content_types.each do |content|
  puts "\nAnalyzing: #{content[:path]}"
  
  # Mock analysis result
  mock_analysis = case content[:expected_type]
                  when :image
                    {
                      type: :image,
                      analysis: { success: true, description: "A landscape photo" },
                      insights: {
                        has_people: false,
                        has_text: false,
                        is_screenshot: false,
                        primary_colors: %w[blue green white],
                        detected_objects: %w[mountain lake trees]
                      }
                    }
                  when :audio
                    {
                      type: :audio,
                      analysis: { success: true },
                      insights: {
                        is_speech: true,
                        sentiment: "neutral",
                        duration_category: "medium",
                        complexity: "complex"
                      }
                    }
                  when :document
                    {
                      type: :document,
                      analysis: { success: true },
                      insights: {
                        document_type: "report",
                        complexity: "complex",
                        length_category: "long",
                        main_topics: %w[analysis data results]
                      }
                    }
                  end
  
  puts "  Type: #{mock_analysis[:type]}"
  puts "  Insights: #{mock_analysis[:insights]}"
end
puts

# Example 6: Multi-Modal Conversation
puts "Example 6: Multi-Modal Conversation"
puts "-" * 50

conversation = OpenAIAgents::MultiModal::MultiModalConversation.new

# Add text message
conversation.add_message(
  role: "user",
  content: "Can you analyze this workspace photo and tell me about the setup?"
)

# Add message with image
conversation.add_message(
  role: "user",
  content: "Here's the photo",
  media: {
    path: "/path/to/workspace.jpg",
    type: :image
  }
)

# Add assistant response
conversation.add_message(
  role: "assistant",
  content: "I can see a well-organized developer workspace with a laptop showing Ruby code, indicating this is likely a Ruby developer's setup. The natural lighting and clean desk suggest a productive environment."
)

# Add audio message
conversation.add_message(
  role: "user",
  content: "I've recorded my thoughts about the setup",
  media: {
    path: "/path/to/thoughts.mp3",
    type: :audio
  }
)

puts "Multi-modal conversation:"
puts "Messages: #{conversation.messages.size}"
puts "Media attachments: #{conversation.media_attachments.size}"
puts "\nConversation flow:"
conversation.messages.each_with_index do |msg, i|
  puts "  #{i + 1}. [#{msg[:role]}] #{msg[:content] || '(media attachment)'}"
end
puts

# Example 7: Multi-Modal Workflow
puts "Example 7: Multi-Modal Workflow Integration"
puts "-" * 50

puts "Example workflow: Content Analysis Pipeline"
puts "\nWorkflow steps:"
puts "  1. Vision Analysis Node - Analyze uploaded image"
puts "  2. Audio Transcription Node - Transcribe associated audio"
puts "  3. Document Query Node - Extract relevant documentation"
puts "  4. Agent Synthesis Node - Combine all insights"
puts

# Mock workflow execution
workflow_result = {
  vision_output: "Detected technical diagram with system architecture",
  audio_output: "Transcribed explanation of the architecture components",
  document_output: "Found matching documentation section about system design",
  final_synthesis: "Complete analysis combining visual, audio, and textual information"
}

puts "Workflow results:"
workflow_result.each do |step, output|
  puts "  #{step}: #{output}"
end
puts

# Example 8: Practical Use Cases
puts "Example 8: Practical Use Cases"
puts "-" * 50

use_cases = [
  {
    name: "Educational Content Analysis",
    description: "Analyze lecture videos by extracting slides (vision), transcribing speech (audio), and referencing textbooks (documents)",
    tools: %w[analyze_image process_audio process_document]
  },
  {
    name: "Customer Support Enhancement",
    description: "Process screenshot issues (vision), voice complaints (audio), and documentation (documents) for comprehensive support",
    tools: %w[analyze_image process_audio process_document]
  },
  {
    name: "Content Moderation",
    description: "Review images for inappropriate content, transcribe audio for policy violations, scan documents for sensitive data",
    tools: %w[analyze_image process_audio process_document]
  },
  {
    name: "Research Assistant",
    description: "Analyze research diagrams, transcribe interviews, process academic papers for literature review",
    tools: %w[analyze_image process_audio process_document]
  }
]

puts "Multi-modal agent use cases:\n\n"
use_cases.each_with_index do |use_case, i|
  puts "#{i + 1}. #{use_case[:name]}"
  puts "   #{use_case[:description]}"
  puts "   Tools: #{use_case[:tools].join(', ')}"
  puts
end

# Example 9: Performance Considerations
puts "Example 9: Performance Considerations"
puts "-" * 50

puts "Multi-modal processing tips:"
puts "1. Image Processing:"
puts "   - Resize large images before processing (max 2048x2048)"
puts "   - Use appropriate quality settings (85% JPEG quality usually sufficient)"
puts "   - Consider caching analyzed results"
puts
puts "2. Audio Processing:"
puts "   - Use appropriate audio formats (MP3, M4A preferred)"
puts "   - Split long audio files into chunks"
puts "   - Consider real-time vs batch processing needs"
puts
puts "3. Document Processing:"
puts "   - Pre-process PDFs to extract text layer"
puts "   - Limit document size for real-time processing"
puts "   - Index large document collections"
puts
puts "4. General Tips:"
puts "   - Process media asynchronously when possible"
puts "   - Implement progress indicators for long operations"
puts "   - Set appropriate timeouts"
puts "   - Monitor API usage and costs"
puts

# Best practices
puts "\n=== Multi-Modal Best Practices ==="
puts "-" * 50
puts <<~PRACTICES
  1. Media Handling:
     - Validate file types and sizes before processing
     - Store media securely with proper access controls
     - Clean up temporary files after processing
     - Implement virus scanning for uploads
  
  2. Processing Strategy:
     - Choose the right model for each modality
     - Process in parallel when independent
     - Cache results for repeated queries
     - Implement fallback strategies
  
  3. Error Handling:
     - Handle API rate limits gracefully
     - Provide meaningful error messages
     - Log processing failures for debugging
     - Implement retry logic with backoff
  
  4. User Experience:
     - Show processing progress indicators
     - Provide preview/thumbnail generation
     - Allow cancellation of long operations
     - Optimize for common use cases
  
  5. Cost Management:
     - Monitor token usage across modalities
     - Implement usage quotas if needed
     - Use smaller models when appropriate
     - Batch process when possible
  
  6. Privacy & Security:
     - Don't store sensitive media unnecessarily
     - Implement data retention policies
     - Use secure transmission methods
     - Comply with privacy regulations
  
  7. Integration:
     - Design clear APIs for each modality
     - Standardize response formats
     - Provide webhooks for async processing
     - Document limitations clearly
PRACTICES

puts "\nMulti-modal agent example completed!"
