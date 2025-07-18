# frozen_string_literal: true

require_relative '../code_validator'

RSpec.describe CodeValidator do
  let(:validator) { CodeValidator.new('spec/fixtures', '.') }
  
  describe '#extract_code_blocks' do
    before do
      Dir.mkdir('spec') unless Dir.exist?('spec')
      Dir.mkdir('spec/fixtures') unless Dir.exist?('spec/fixtures')
      
      File.write('spec/fixtures/test_guide.md', <<~MARKDOWN)
        # Test Guide
        
        Here's a Ruby example:
        
        ```ruby
        puts "Hello, World!"
        ```
        
        And another:
        
        ```ruby
        class TestClass
          def initialize(name)
            @name = name
          end
        end
        ```
        
        Some other code:
        
        ```javascript
        console.log("Not Ruby");
        ```
        
        ```ruby
        # This is Ruby
        result = 1 + 2
        ```
      MARKDOWN
    end
    
    after do
      FileUtils.rm_rf('spec') if Dir.exist?('spec')
    end
    
    it 'extracts Ruby code blocks from markdown files' do
      blocks = validator.extract_code_blocks
      
      expect(blocks.length).to eq(3)
      expect(blocks[0].content).to include('puts "Hello, World!"')
      expect(blocks[1].content).to include('class TestClass')
      expect(blocks[2].content).to include('result = 1 + 2')
    end
    
    it 'records correct file and line information' do
      blocks = validator.extract_code_blocks
      
      expect(blocks[0].file.to_s).to eq('test_guide.md')
      expect(blocks[0].line_number).to eq(6)  # Line after ```ruby
      expect(blocks[1].line_number).to eq(11) # Line after second ```ruby
    end
  end
  
  describe '#validate_code_blocks' do
    let(:valid_block) { CodeValidator::CodeBlock.new('puts "test"', 'test.md', 1) }
    let(:invalid_block) { CodeValidator::CodeBlock.new('puts "unclosed string', 'test.md', 5) }
    
    it 'validates syntactically correct code' do
      results = validator.validate_code_blocks([valid_block])
      
      expect(results.length).to eq(1)
      expect(results[0].success).to be true
    end
    
    it 'catches syntax errors' do
      results = validator.validate_code_blocks([invalid_block])
      
      expect(results.length).to eq(1)
      expect(results[0].success).to be false
      expect(results[0].error).to include('syntax error')
    end
  end
end