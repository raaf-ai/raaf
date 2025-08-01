# RAAF Misc

[![Gem Version](https://badge.fury.io/rb/raaf-misc.svg)](https://badge.fury.io/rb/raaf-misc)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The **RAAF Misc** gem provides miscellaneous utilities and components for the Ruby AI Agents Factory (RAAF) ecosystem. It consolidates several smaller components into a single gem for easier management and installation.

## Overview

RAAF (Ruby AI Agents Factory) Misc consolidates the following components:

- **Voice Workflows** - Voice interaction and speech processing capabilities
- **Prompt Management** - Prompt utilities and management tools  
- **Extensions** - Plugin architecture and extension points
- **Data Pipeline** - Data processing and transformation utilities
- **Multimodal** - Multi-modal content processing (text, images, audio)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'raaf-misc', '~> 1.0'
```

And then execute:

```bash
bundle install
```

## Components

### Voice Workflows

Voice interaction and speech processing capabilities for AI agents.

```ruby
require 'raaf-misc'

# Create voice workflow
voice = RAAF::Misc::Voice::VoiceWorkflow.new

# Configure speech settings
voice.configure do |config|
  config.speech_provider = :azure
  config.voice_model = "neural"
  config.language = "en-US"
end

# Process voice input
result = voice.process_audio(audio_data)
```

### Prompt Management

Utilities for managing and organizing prompts across your AI agents.

```ruby
require 'raaf-misc'

# Create prompt manager
prompts = RAAF::Misc::Prompts::Manager.new

# Register prompts
prompts.register(:customer_service, "You are a helpful customer service agent")
prompts.register(:technical_support, "You are a technical support specialist")

# Use prompts
prompt = prompts.get(:customer_service)
```

### Extensions

Plugin architecture and extension points for customizing RAAF functionality.

```ruby
require 'raaf-misc'

# Create extension manager
extensions = RAAF::Misc::Extensions::Manager.new

# Register extension
extensions.register(:custom_tool) do |config|
  config.name = "Custom Tool"
  config.description = "A custom tool for specific tasks"
  config.handler = CustomToolHandler
end

# Load extensions
extensions.load_all
```

### Data Pipeline

Data processing and transformation utilities for AI workflows.

```ruby
require 'raaf-misc'

# Create data pipeline
pipeline = RAAF::Misc::DataPipeline::Processor.new

# Add processing steps
pipeline.add_step(:extract, DataExtractor.new)
pipeline.add_step(:transform, DataTransformer.new)
pipeline.add_step(:load, DataLoader.new)

# Process data
result = pipeline.process(input_data)
```

### Multimodal Processing

Multi-modal content processing for text, images, and audio.

```ruby
require 'raaf-misc'

# Create multimodal processor
multimodal = RAAF::Misc::Multimodal::Processor.new

# Process different content types
text_result = multimodal.process_text("Hello world")
image_result = multimodal.process_image(image_data)
audio_result = multimodal.process_audio(audio_data)

# Combined processing
combined_result = multimodal.process_combined([
  { type: :text, content: "Describe this image" },
  { type: :image, content: image_data }
])
```

## Usage Examples

### Voice-Enabled Agent

```ruby
require 'raaf-misc'
require 'raaf-core'

# Create agent with voice capabilities
agent = RAAF::Agent.new(
  name: "VoiceAssistant",
  instructions: "You are a voice-enabled assistant",
  model: "gpt-4o"
)

# Add voice workflow
voice = RAAF::Misc::Voice::VoiceWorkflow.new
agent.add_capability(:voice, voice)

# Process voice input
runner = RAAF::Runner.new(agent: agent)
result = runner.run_voice(audio_input)
```

### Custom Extension

```ruby
require 'raaf-misc'

class CustomAnalyzer
  def analyze(data)
    # Custom analysis logic
    { sentiment: :positive, confidence: 0.95 }
  end
end

# Register as extension
extensions = RAAF::Misc::Extensions::Manager.new
extensions.register(:sentiment_analyzer) do |config|
  config.handler = CustomAnalyzer
  config.priority = 10
end

# Use extension
analyzer = extensions.get(:sentiment_analyzer)
result = analyzer.analyze("Great product!")
```

### Data Processing Pipeline

```ruby
require 'raaf-misc'

# Create processing pipeline
pipeline = RAAF::Misc::DataPipeline::Processor.new

# Add steps
pipeline.add_step(:clean) do |data|
  data.strip.downcase
end

pipeline.add_step(:tokenize) do |data|
  data.split(/\s+/)
end

pipeline.add_step(:analyze) do |tokens|
  { word_count: tokens.length, tokens: tokens }
end

# Process data
result = pipeline.process("Hello World Example")
# => { word_count: 3, tokens: ["hello", "world", "example"] }
```

## Relationship with Other Gems

### Foundation Dependencies

- **raaf-core** - Uses core interfaces and base classes
- **raaf-logging** - Uses logging for component operations

### Enhanced by Infrastructure

- **raaf-configuration** - Uses configuration for component settings
- **raaf-tracing** - Traces component operations and performance
- **raaf-providers** - Uses providers for speech and multimodal processing

### Integrates with Agent Features

- **raaf-memory** - Stores prompt templates and extension configurations
- **raaf-tools-basic** - Provides basic tools that can be extended
- **raaf-tools-advanced** - Uses advanced tools in data pipelines

### Platform Integration

- **raaf-rails** - Integrates components with Rails applications
- **raaf-streaming** - Provides streaming capabilities for voice and multimodal
- **raaf-testing** - Provides testing utilities for all components

### Enterprise Features

- **raaf-guardrails** - Validates component inputs and outputs
- **raaf-compliance** - Ensures components meet compliance requirements
- **raaf-security** - Secures component communications and data
- **raaf-monitoring** - Monitors component performance and usage

## Architecture

### Core Components

```
RAAF::Misc::
├── Voice/
│   ├── VoiceWorkflow        # Voice processing workflow
│   ├── SpeechRecognition    # Speech-to-text
│   └── TextToSpeech         # Text-to-speech
├── Prompts/
│   ├── Manager              # Prompt management
│   ├── Template             # Prompt templates
│   └── Registry             # Prompt registry
├── Extensions/
│   ├── Manager              # Extension management
│   ├── Loader               # Extension loading
│   └── Registry             # Extension registry
├── DataPipeline/
│   ├── Processor            # Data processing
│   ├── Step                 # Processing steps
│   └── Pipeline             # Pipeline management
└── Multimodal/
    ├── Processor            # Multimodal processing
    ├── TextProcessor        # Text processing
    ├── ImageProcessor       # Image processing
    └── AudioProcessor       # Audio processing
```

### Extension Points

Each component provides extension points for customization:

1. **Voice Extensions** - Custom speech providers and processors
2. **Prompt Extensions** - Custom prompt generators and validators
3. **Pipeline Extensions** - Custom processing steps and transformers
4. **Multimodal Extensions** - Custom content processors and analyzers

## Advanced Features

### Component Configuration

```ruby
# Global configuration
RAAF::Misc.configure do |config|
  config.voice.default_provider = :azure
  config.prompts.cache_enabled = true
  config.extensions.auto_load = true
  config.data_pipeline.parallel_processing = true
  config.multimodal.image_processing = true
end
```

### Plugin Development

```ruby
# Create custom plugin
class MyPlugin < RAAF::Misc::Extensions::Base
  def initialize(config)
    @config = config
  end
  
  def execute(context)
    # Plugin logic
  end
end

# Register plugin
RAAF::Misc::Extensions.register(:my_plugin, MyPlugin)
```

### Performance Optimization

```ruby
# Enable caching
RAAF::Misc.configure do |config|
  config.caching.enabled = true
  config.caching.ttl = 3600
  config.caching.backend = :redis
end

# Parallel processing
pipeline = RAAF::Misc::DataPipeline::Processor.new
pipeline.configure do |config|
  config.parallel = true
  config.max_threads = 4
end
```

## Best Practices

1. **Use Appropriate Components** - Choose the right component for your use case
2. **Configure Properly** - Set up components with appropriate settings
3. **Handle Errors Gracefully** - Implement proper error handling
4. **Monitor Performance** - Track component performance and usage
5. **Extend Carefully** - Follow extension patterns and conventions

## Development

### Running Tests

```bash
cd misc/
bundle exec rspec
```

### Testing Components

```ruby
# Test voice workflow
RSpec.describe RAAF::Misc::Voice::VoiceWorkflow do
  it "processes audio correctly" do
    voice = described_class.new
    result = voice.process_audio(sample_audio)
    expect(result).to be_successful
  end
end
```

### Adding New Components

1. Create component directory under `lib/raaf/misc/`
2. Implement component following existing patterns
3. Add tests under `spec/`
4. Update main library file to require component
5. Document component in README

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/new-feature`)
3. Commit your changes (`git commit -m 'Add new feature'`)
4. Push to the branch (`git push origin feature/new-feature`)
5. Open a Pull Request

## License

This gem is available as open source under the terms of the [MIT License](LICENSE).

## Support

- **Documentation**: [Ruby AI Agents Factory Docs](https://raaf-ai.github.io/ruby-ai-agents-factory/)
- **Issues**: [GitHub Issues](https://github.com/raaf-ai/ruby-ai-agents-factory/issues)
- **Discussions**: [GitHub Discussions](https://github.com/raaf-ai/ruby-ai-agents-factory/discussions)
- **Email**: bert.hajee@enterprisemodules.com

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a list of changes and version history.