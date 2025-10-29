# Initial Spec Idea

## User's Initial Description

Implement automatic continuation support in RAAF to handle token limit truncation. When an LLM response gets cut off due to output token limits (finish_reason: "length"), RAAF should automatically detect this, continue the generation, and intelligently merge the responses. Support multiple output formats (CSV, Markdown, JSON) with format-specific merge strategies optimized for high success rates.

**Key Requirements (based on conversation):**
- Detect finish_reason: "length" at provider level
- Support CSV (95% success), Markdown (85-95% success), JSON (60-70% success)
- Opt-in feature (backward compatible)
- Configurable at Agent DSL level
- Format-specific mergers with intelligent concatenation
- Track continuation metadata (count, tokens, success)
- Fail gracefully with partial results on merge errors
- Primary use case: Large dataset generation (company lists, data extraction)

## Metadata

- Date Created: 2025-10-29
- Spec Name: automatic-continuation-support
- Spec Path: /Users/hajee/Enterprise Modules Dropbox/Bert Hajee/enterprisemodules/work/prospects_radar/vendor/local_gems/raaf/.agent-os/specs/2025-10-29-automatic-continuation-support
