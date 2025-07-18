# Misc API Reference

Complete Ruby API documentation for RAAF Misc components including Voice, Extensions, Data Pipeline, Multi-modal, and Prompts functionality.

## Table of Contents

1. [Voice](#voice)
   - [VoiceWorkflow](#voiceworkflow)
   - [Speech Recognition](#speech-recognition)
   - [Text-to-Speech](#text-to-speech)
2. [Extensions](#extensions)
   - [Extension System](#extension-system)
   - [Creating Extensions](#creating-extensions)
3. [Data Pipeline](#data-pipeline)
   - [Pipeline Builder](#pipeline-builder)
   - [Pipeline Stages](#pipeline-stages)
4. [Multi-modal](#multi-modal)
   - [Image Processing](#image-processing)
   - [Multi-modal Agents](#multi-modal-agents)
5. [Prompts](#prompts)
   - [Prompt Templates](#prompt-templates)
   - [Dynamic Prompts](#dynamic-prompts)

## Voice

### VoiceWorkflow

Main class for voice-enabled agent interactions.

```ruby
# Constructor
RAAF::Misc::Voice::VoiceWorkflow.new(
  transcription_model: "whisper-1",    # Speech-to-text model
  tts_model: "tts-1-hd",              # Text-to-speech model
  voice: "nova",                      # Voice selection
  language: "en",                     # Primary language
  auto_detect_language: true,         # Auto-detect input language
  audio_format: "mp3"                 # Output audio format
)
```

#### Core Methods

```ruby
# Process audio file with agent
workflow.process_audio_file(
  file_path: String,               # Path to audio file
  agent: Agent,                    # Agent to process with
  options: Hash                    # Processing options
)

# Transcribe audio to text
workflow.transcribe_audio(
  file_path: String,               # Audio file path
  language: String,                # Optional language hint
  prompt: String                   # Optional context prompt
)

# Convert text to speech
workflow.synthesize_speech(
  text: String,                    # Text to synthesize
  voice: String,                   # Optional voice override
  speed: Float                     # Speech speed (0.25-4.0)
)

# Play audio file
workflow.play_audio(file_path)     # Platform-specific playback
```

#### Example Usage

```ruby
# Create voice workflow
workflow = RAAF::Misc::Voice::VoiceWorkflow.new(
  voice: "alloy",
  tts_model: "tts-1-hd"
)

# Create agent
agent = RAAF::Agent.new(
  name: "VoiceAssistant",
  instructions: "You are a helpful voice assistant. Keep responses concise.",
  model: "gpt-4"
)

# Process voice input
result = workflow.process_audio_file(
  file_path: "user_question.mp3",
  agent: agent
)

# Result includes:
# - transcription: "What's the weather like today?"
# - response_text: "I'd be happy to help with weather information..."
# - response_audio: "response_12345.mp3"

# Play response
workflow.play_audio(result[:response_audio])
```

### Speech Recognition

```ruby
# Basic transcription
transcriber = RAAF::Misc::Voice::Transcriber.new(
  model: "whisper-1",
  api_key: ENV['OPENAI_API_KEY']
)

text = transcriber.transcribe(
  file_path: "audio.mp3"
)

# Advanced transcription with options
result = transcriber.transcribe(
  file_path: "audio.mp3",
  language: "en",                  # Language hint
  prompt: "Meeting transcript:",   # Context prompt
  temperature: 0.2,                # Lower = more deterministic
  response_format: "verbose_json"  # Detailed output
)
```

### Text-to-Speech

```ruby
# Basic TTS
tts = RAAF::Misc::Voice::TextToSpeech.new(
  model: "tts-1-hd",
  voice: "nova"
)

audio_file = tts.synthesize(
  text: "Hello, welcome to RAAF voice capabilities!",
  output_path: "welcome.mp3"
)

# Available voices
VOICES = {
  alloy: "Neutral and balanced",
  echo: "Warm and conversational", 
  fable: "Expressive and dynamic",
  onyx: "Deep and authoritative",
  nova: "Friendly and upbeat",
  shimmer: "Soft and gentle"
}
```

## Extensions

### Extension System

Framework for extending RAAF functionality with plugins.

```ruby
# Define Extension
class MyExtension < RAAF::Misc::Extensions::BaseExtension
  def self.extension_info
    {
      name: :my_extension,
      type: :tool,                  # :tool, :provider, :processor
      version: "1.0.0",
      dependencies: []
    }
  end
  
  def setup(config)
    # Extension setup logic
    @config = config
  end
  
  def activate
    # Extension activation logic
    register_tools
    setup_hooks
  end
  
  def deactivate
    # Cleanup logic
  end
end
```

### Creating Extensions

#### Tool Extension

```ruby
class WeatherExtension < RAAF::Misc::Extensions::BaseExtension
  def self.extension_info
    {
      name: :weather_tools,
      type: :tool,
      version: "1.0.0",
      description: "Weather information tools"
    }
  end
  
  def activate
    # Register weather tools
    RAAF::Extensions.register_tool(:get_weather) do |city:|
      fetch_weather_data(city)
    end
    
    RAAF::Extensions.register_tool(:weather_forecast) do |city:, days: 5|
      fetch_forecast(city, days)
    end
  end
  
  private
  
  def fetch_weather_data(city)
    # Implementation
    "Sunny, 72°F in #{city}"
  end
  
  def fetch_forecast(city, days)
    # Implementation
    "#{days}-day forecast for #{city}"
  end
end

# Load and activate
RAAF::Misc::Extensions.load_extension(WeatherExtension)
RAAF::Misc::Extensions.activate(:weather_tools)
```

#### Provider Extension

```ruby
class CustomProviderExtension < RAAF::Misc::Extensions::BaseExtension
  def self.extension_info
    {
      name: :custom_provider,
      type: :provider,
      version: "1.0.0"
    }
  end
  
  def activate
    # Register custom model provider
    provider = CustomModelProvider.new(@config)
    RAAF::Models.register_provider(:custom, provider)
  end
  
  class CustomModelProvider
    def initialize(config)
      @api_key = config[:api_key]
      @endpoint = config[:endpoint]
    end
    
    def chat_completion(messages:, model:, **options)
      # Custom API implementation
    end
  end
end
```

### Extension Management

```ruby
# List available extensions
RAAF::Misc::Extensions.available
# => [:weather_tools, :custom_provider, :database_tools]

# Check if extension is loaded
RAAF::Misc::Extensions.loaded?(:weather_tools)
# => true

# Get extension info
RAAF::Misc::Extensions.info(:weather_tools)
# => { name: :weather_tools, type: :tool, version: "1.0.0", ... }

# Deactivate extension
RAAF::Misc::Extensions.deactivate(:weather_tools)

# Configure extension
RAAF::Misc::Extensions.configure(:weather_tools) do |config|
  config.api_key = ENV['WEATHER_API_KEY']
  config.cache_duration = 3600
end
```

## Data Pipeline

### Pipeline Builder

Create data processing pipelines for agents.

```ruby
# Constructor
pipeline = RAAF::Misc::DataPipeline::Pipeline.new(
  name: "DataProcessor",
  stages: []                       # Pipeline stages
)

# Add stages
pipeline.add_stage(:extract, &extractor)
pipeline.add_stage(:transform, &transformer)
pipeline.add_stage(:load, &loader)

# Execute pipeline
result = pipeline.execute(input_data)
```

### Pipeline Stages

#### Built-in Stages

```ruby
# Text extraction stage
extractor = RAAF::Misc::DataPipeline::Stages::TextExtractor.new(
  formats: [:pdf, :docx, :txt],
  encoding: "UTF-8"
)

# Data transformation stage
transformer = RAAF::Misc::DataPipeline::Stages::DataTransformer.new do |data|
  # Transform logic
  data.map { |item| transform_item(item) }
end

# Validation stage
validator = RAAF::Misc::DataPipeline::Stages::Validator.new(
  schema: {
    type: "object",
    properties: {
      name: { type: "string" },
      value: { type: "number" }
    },
    required: ["name", "value"]
  }
)

# Agent processing stage
agent_processor = RAAF::Misc::DataPipeline::Stages::AgentProcessor.new(
  agent: data_agent,
  batch_size: 10
)
```

#### Custom Stages

```ruby
class CustomStage < RAAF::Misc::DataPipeline::Stage
  def initialize(options = {})
    @options = options
    super()
  end
  
  def process(input)
    # Process input data
    output = transform_data(input)
    
    # Pass to next stage
    emit(output)
  end
  
  def validate_input(input)
    # Validate input before processing
    raise "Invalid input" unless input.is_a?(Array)
  end
end
```

### Pipeline Example

```ruby
# Create ETL pipeline
etl_pipeline = RAAF::Misc::DataPipeline::Pipeline.new(name: "ETL")

# Extract stage - read from multiple sources
etl_pipeline.add_stage(:extract) do |config|
  files = Dir.glob(config[:pattern])
  files.map { |f| read_file(f) }
end

# Transform stage - process with agent
transform_agent = RAAF::Agent.new(
  name: "DataTransformer",
  instructions: "Extract structured data from text."
)

etl_pipeline.add_stage(:transform) do |data|
  data.map do |item|
    result = transform_agent.run(item)
    parse_response(result)
  end
end

# Load stage - save to database
etl_pipeline.add_stage(:load) do |records|
  records.each do |record|
    Database.insert(record)
  end
end

# Execute pipeline
config = { pattern: "data/*.txt" }
results = etl_pipeline.execute(config)
```

## Multi-modal

### Image Processing

Handle images and visual content with agents.

```ruby
# Multi-modal agent
multi_modal = RAAF::Misc::MultiModal::Agent.new(
  name: "VisionAssistant",
  model: "gpt-4-vision-preview",
  instructions: "Analyze images and answer questions about them."
)

# Process image
result = multi_modal.process_image(
  image_path: "chart.png",
  prompt: "What trends do you see in this chart?"
)

# Process multiple images
results = multi_modal.process_images(
  images: ["photo1.jpg", "photo2.jpg"],
  prompt: "Compare these two images"
)
```

### Multi-modal Agents

#### Image Analysis

```ruby
analyzer = RAAF::Misc::MultiModal::ImageAnalyzer.new

# Analyze single image
analysis = analyzer.analyze(
  image: "product.jpg",
  tasks: [:objects, :text, :colors, :quality]
)

# Returns:
{
  objects: ["laptop", "desk", "coffee cup"],
  text: ["MacBook Pro", "RAAF Documentation"],
  dominant_colors: ["#FFFFFF", "#000000", "#A0A0A0"],
  quality_score: 0.92
}

# Batch analysis
results = analyzer.batch_analyze(
  images: Dir.glob("images/*.jpg"),
  tasks: [:objects, :quality]
)
```

#### Vision-Language Tasks

```ruby
# Visual Q&A
vqa = RAAF::Misc::MultiModal::VisualQA.new(
  model: "gpt-4-vision-preview"
)

answer = vqa.ask(
  image: "diagram.png",
  question: "What does this diagram represent?"
)

# Image captioning
captioner = RAAF::Misc::MultiModal::ImageCaptioner.new

caption = captioner.generate_caption(
  image: "sunset.jpg",
  style: :detailed  # :brief, :detailed, :poetic
)

# Visual reasoning
reasoner = RAAF::Misc::MultiModal::VisualReasoner.new

reasoning = reasoner.analyze(
  images: ["before.jpg", "after.jpg"],
  task: "Explain what changed between these images"
)
```

## Prompts

### Prompt Templates

Manage and use prompt templates.

```ruby
# Define template
template = RAAF::Misc::Prompts::Template.new(
  name: "customer_support",
  template: <<~PROMPT
    You are a customer support agent for {company_name}.
    
    Customer Profile:
    - Name: {customer_name}
    - Account Type: {account_type}
    - History: {purchase_history}
    
    Guidelines:
    - Be friendly and professional
    - {additional_guidelines}
    
    Current Issue: {issue_description}
  PROMPT
)

# Use template
prompt = template.render(
  company_name: "RAAF Corp",
  customer_name: "John Doe",
  account_type: "Premium",
  purchase_history: "3 previous purchases",
  additional_guidelines: "Offer discount if appropriate",
  issue_description: "Product not working as expected"
)
```

### Dynamic Prompts

Create prompts that adapt based on context.

```ruby
# Dynamic prompt builder
builder = RAAF::Misc::Prompts::DynamicBuilder.new

builder.base_prompt("You are an AI assistant")

builder.add_section(:expertise) do |context|
  if context[:technical]
    "with deep technical knowledge in #{context[:domain]}"
  else
    "focused on clear, non-technical explanations"
  end
end

builder.add_section(:tone) do |context|
  case context[:audience]
  when :child
    "Use simple language and be playful"
  when :professional
    "Maintain a formal, business-appropriate tone"
  when :casual
    "Be conversational and friendly"
  end
end

# Generate prompt
prompt = builder.build(
  technical: true,
  domain: "machine learning",
  audience: :professional
)
# => "You are an AI assistant with deep technical knowledge in machine learning. Maintain a formal, business-appropriate tone."
```

### Prompt Library

```ruby
# Load prompt library
library = RAAF::Misc::Prompts::Library.new(
  path: "prompts/"
)

# Get prompt by name
support_prompt = library.get(:customer_support)

# Search prompts
results = library.search("technical writing")

# Categories
library.categories
# => [:support, :analysis, :creative, :technical]

library.by_category(:technical)
# => [<Prompt: code_review>, <Prompt: debugging>, ...]

# Add custom prompt
library.add_prompt(
  name: :data_analyst,
  category: :analysis,
  template: "You are a data analyst specializing in {domain}...",
  variables: [:domain, :dataset_type],
  examples: [
    { domain: "finance", dataset_type: "time series" }
  ]
)

# Export/import
library.export_to_file("my_prompts.json")
library.import_from_file("shared_prompts.json")
```

### Prompt Optimization

```ruby
# Optimize prompts for better performance
optimizer = RAAF::Misc::Prompts::Optimizer.new

optimized = optimizer.optimize(
  prompt: original_prompt,
  goals: [:clarity, :conciseness, :effectiveness],
  model: "gpt-4"
)

# A/B test prompts
tester = RAAF::Misc::Prompts::ABTester.new

results = tester.test(
  variants: {
    a: prompt_a,
    b: prompt_b
  },
  test_cases: test_inputs,
  evaluator: ->(response) { evaluate_quality(response) }
)

# Returns:
{
  variant_a: { success_rate: 0.85, avg_score: 8.2 },
  variant_b: { success_rate: 0.92, avg_score: 9.1 },
  recommendation: :variant_b
}
```

## Integration Examples

### Voice + Agent Pipeline

```ruby
# Voice-enabled data pipeline
voice_pipeline = RAAF::Misc::DataPipeline::Pipeline.new(name: "VoiceData")

# Stage 1: Voice to text
voice_workflow = RAAF::Misc::Voice::VoiceWorkflow.new
voice_pipeline.add_stage(:transcribe) do |audio_files|
  audio_files.map { |f| voice_workflow.transcribe_audio(f) }
end

# Stage 2: Process with agent
agent = RAAF::Agent.new(
  name: "DataExtractor",
  instructions: "Extract key information from transcripts."
)

voice_pipeline.add_stage(:extract) do |transcripts|
  transcripts.map { |t| agent.run(t) }
end

# Stage 3: Structure data
voice_pipeline.add_stage(:structure) do |responses|
  responses.map { |r| parse_to_json(r) }
end

# Execute
audio_files = Dir.glob("recordings/*.mp3")
structured_data = voice_pipeline.execute(audio_files)
```

### Multi-modal Extension

```ruby
class VisionExtension < RAAF::Misc::Extensions::BaseExtension
  def self.extension_info
    {
      name: :vision_tools,
      type: :tool,
      version: "1.0.0"
    }
  end
  
  def activate
    # Add image analysis tool
    RAAF::Extensions.register_tool(:analyze_image) do |image_path:, task: :general|
      analyzer = RAAF::Misc::MultiModal::ImageAnalyzer.new
      analyzer.analyze(image: image_path, tasks: [task])
    end
    
    # Add visual QA tool
    RAAF::Extensions.register_tool(:visual_qa) do |image:, question:|
      vqa = RAAF::Misc::MultiModal::VisualQA.new
      vqa.ask(image: image, question: question)
    end
  end
end

# Use in agent
agent = RAAF::Agent.new(
  name: "VisionAgent",
  instructions: "Help users understand images.",
  tools: [:analyze_image, :visual_qa]
)
```

For more information on core functionality, see the [Core API Reference](../core/API_REFERENCE.md).