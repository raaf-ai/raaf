# frozen_string_literal: true

puts "Creating sample evaluation data..."

# Create sample users (if User model exists)
if defined?(User)
  demo_user = User.find_or_create_by!(email: 'demo@example.com') do |user|
    user.password = 'password'
    user.password_confirmation = 'password'
  end
  puts "Created demo user: demo@example.com"
end

# Sample agent names and models
agents = ['TestAgent', 'ResearchAgent', 'WriterAgent', 'AnalyzerAgent', 'SupportAgent']
models = ['gpt-4o', 'gpt-4-turbo', 'claude-3-5-sonnet-20241022', 'claude-3-opus-20240229', 'gemini-pro']
statuses = ['completed', 'completed', 'completed', 'failed']

# Create 50 evaluation spans
puts "Creating 50 evaluation spans..."
50.times do |i|
  agent = agents.sample
  model = models.sample
  status = statuses.sample

  input_content = [
    "Analyze the following data and provide insights.",
    "Write a summary of the given information.",
    "Research the topic and compile findings.",
    "Help me understand this concept.",
    "Review this code and suggest improvements."
  ].sample

  output_content = if status == 'completed'
    [
      "Based on my analysis, I found several key insights. First, the data shows a clear trend...",
      "Here's a comprehensive summary of the information provided. The main points are...",
      "My research reveals several important findings about this topic...",
      "Let me explain this concept in simple terms. The fundamental idea is...",
      "After reviewing the code, I have several suggestions for improvement..."
    ].sample
  else
    nil
  end

  RAAF::Eval::Models::EvaluationSpan.create!(
    span_id: SecureRandom.uuid,
    trace_id: SecureRandom.uuid,
    span_type: 'agent',
    source: 'production',
    span_data: {
      'agent_name' => agent,
      'model' => model,
      'instructions' => "You are a helpful #{agent}. Assist users with their queries.",
      'input_messages' => [
        { 'role' => 'user', 'content' => input_content }
      ],
      'output_messages' => output_content ? [
        { 'role' => 'assistant', 'content' => output_content }
      ] : [],
      'tool_calls' => i % 3 == 0 ? [
        {
          'name' => 'search_tool',
          'arguments' => { 'query' => 'sample query' },
          'result' => 'Search results returned successfully'
        }
      ] : [],
      'handoffs' => i % 5 == 0 ? [
        {
          'to_agent' => agents.sample,
          'context' => { 'reason' => 'Requires specialized knowledge' }
        }
      ] : [],
      'metadata' => {
        'tokens' => {
          'input' => rand(20..100),
          'output' => rand(50..200),
          'total' => rand(70..300)
        },
        'cost' => {
          'input' => rand(0.0001..0.002).round(4),
          'output' => rand(0.0002..0.004).round(4),
          'total' => rand(0.0003..0.006).round(4)
        },
        'latency_ms' => rand(500..3000),
        'ttft_ms' => rand(100..500),
        'temperature' => [0.3, 0.5, 0.7, 0.9, 1.0].sample,
        'max_tokens' => [500, 1000, 1500, 2000].sample
      },
      'status' => status
    }
  )
end

puts "Created 50 evaluation spans"

# Create 10 completed evaluation sessions
puts "Creating completed evaluation sessions..."
10.times do |i|
  baseline_span = RAAF::Eval::Models::EvaluationSpan.where(span_data: { 'status' => 'completed' }).sample
  next unless baseline_span

  session = RAAF::Eval::UI::Session.create!(
    name: "Evaluation #{i + 1}: #{['Temperature', 'Model', 'Token Limit', 'Prompt'].sample} Test",
    description: "Testing different configurations to optimize agent performance",
    session_type: 'saved',
    status: 'completed',
    baseline_span_id: baseline_span.id,
    started_at: rand(1..30).days.ago,
    completed_at: rand(1..24).hours.ago,
    metadata: {
      'configurations_tested' => rand(2..5)
    }
  )

  # Create configurations for this session
  rand(2..4).times do |config_idx|
    RAAF::Eval::UI::SessionConfiguration.create!(
      raaf_eval_ui_session_id: session.id,
      name: "Config #{config_idx + 1}",
      configuration: {
        model: models.sample,
        temperature: [0.3, 0.5, 0.7, 0.9].sample,
        max_tokens: [500, 1000, 1500].sample,
        top_p: 1.0,
        frequency_penalty: 0.0,
        presence_penalty: 0.0
      },
      display_order: config_idx
    )
  end

  # Create results
  session.configurations.each do |config|
    RAAF::Eval::UI::SessionResult.create!(
      raaf_eval_ui_session_id: session.id,
      raaf_eval_ui_session_configuration_id: config.id,
      status: 'completed'
    )
  end
end

puts "Created 10 completed evaluation sessions"

# Create 5 draft sessions
puts "Creating draft sessions..."
5.times do |i|
  baseline_span = RAAF::Eval::Models::EvaluationSpan.where(span_data: { 'status' => 'completed' }).sample
  next unless baseline_span

  RAAF::Eval::UI::Session.create!(
    name: "Draft Evaluation #{i + 1}",
    description: "Work in progress evaluation",
    session_type: 'draft',
    status: 'pending',
    baseline_span_id: baseline_span.id
  )
end

puts "Created 5 draft sessions"

puts "\n" + "="*50
puts "Sample data created successfully!"
puts "="*50
puts "\nYou can now:"
puts "1. Start the server: rails server"
puts "2. Visit: http://localhost:3000/eval"
puts "3. Login with: demo@example.com / password"
puts "\nTotal records created:"
puts "- 50 evaluation spans"
puts "- 10 completed evaluation sessions"
puts "- 5 draft sessions"
puts "="*50
