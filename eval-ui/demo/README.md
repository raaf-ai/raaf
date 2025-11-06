# RAAF Eval UI Demo Application

This is a demo Rails application showcasing the RAAF Eval UI engine with sample data and configurations.

## Setup

1. Install dependencies:
```bash
cd demo
bundle install
```

2. Set up the database:
```bash
rails db:create
rails db:migrate
rails db:seed
```

3. Start the server:
```bash
rails server
```

4. Visit http://localhost:3000/eval to access the evaluation UI

## Features Demonstrated

### 1. Span Browsing
- Browse recent evaluation spans
- Filter by agent, model, status, and date range
- Search for specific spans
- View detailed span information

### 2. Evaluation Setup
- Select spans for evaluation
- Modify prompts in Monaco Editor
- Adjust AI settings (temperature, max tokens, etc.)
- Real-time validation and token counting

### 3. Evaluation Execution
- Run evaluations with live progress updates
- View estimated time remaining
- Cancel running evaluations
- Retry failed evaluations

### 4. Results Comparison
- Side-by-side comparison of baseline vs new results
- Diff highlighting (additions, deletions, modifications)
- Metrics comparison with delta indicators
- Export results to JSON/CSV

### 5. Session Management
- Save evaluations as named sessions
- Load and resume saved sessions
- Archive old sessions
- Update session metadata

## Sample Data

The seed file creates:
- 50 evaluation spans from various agents and models
- 10 completed evaluation sessions
- 5 draft evaluation sessions
- Sample configurations with different temperature and model settings

## Authentication

The demo app uses a simple session-based authentication system. To log in:

**Username:** demo@example.com
**Password:** password

## Configuration

The engine is mounted at `/eval` and configured in `config/initializers/raaf_eval_ui.rb`:

```ruby
RAAF::Eval::UI.configure do |config|
  config.authentication_method = :authenticate_user!
  config.current_user_method = :current_user
  config.layout = "application"
  config.inherit_assets = true
end
```

## Customization

### Using Your Own Layout

Edit `app/views/layouts/application.html.erb` to customize the layout.

### Adding Custom Authentication

Edit `app/controllers/application_controller.rb` to integrate with your authentication system (Devise, Sorcery, etc.).

### Connecting to Real Evaluation Data

Replace the sample data in `db/seeds.rb` with connections to your actual RAAF tracing data:

```ruby
# In db/seeds.rb
# Connect to your production spans
production_spans = RAAF::Eval::Models::EvaluationSpan.where(source: 'production')
```

## Testing

Run the test suite:

```bash
rspec
```

Run specific test types:

```bash
# Integration tests
rspec spec/integration

# System tests (with browser)
rspec spec/system

# Performance tests
rspec spec/performance
```

## Deployment

See the main README for deployment instructions:
- [../README.md](../README.md)

## Troubleshooting

### Monaco Editor not loading
Make sure JavaScript is enabled and importmap is properly configured.

### Turbo Streams not updating
Check that Redis is running if using ActionCable for real-time updates.

### Database connection errors
Ensure PostgreSQL is installed and running, and database credentials are correct in `config/database.yml`.

## Support

For issues or questions:
- Open an issue on GitHub
- Check the main documentation
- Join our community chat
