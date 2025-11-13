# frozen_string_literal: true

# Load all built-in evaluators
# This file is required by EvaluatorRegistry for auto-registration

# Quality evaluators (4)
require_relative "quality/semantic_similarity"
require_relative "quality/coherence"
require_relative "quality/hallucination_detection"
require_relative "quality/relevance"

# Performance evaluators (3)
require_relative "performance/token_efficiency"
require_relative "performance/latency"
require_relative "performance/throughput"

# Regression evaluators (3)
require_relative "regression/no_regression"
require_relative "regression/token_regression"
require_relative "regression/latency_regression"

# Safety evaluators (3)
require_relative "safety/bias_detection"
require_relative "safety/toxicity_detection"
require_relative "safety/compliance"

# Statistical evaluators (3)
require_relative "statistical/consistency"
require_relative "statistical/statistical_significance"
require_relative "statistical/effect_size"

# Structural evaluators (3)
require_relative "structural/json_validity"
require_relative "structural/schema_match"
require_relative "structural/format_compliance"

# LLM evaluators (3)
require_relative "llm/llm_judge"
require_relative "llm/quality_score"
require_relative "llm/rubric_evaluation"
