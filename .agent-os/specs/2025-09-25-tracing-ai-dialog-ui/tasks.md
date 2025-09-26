# Spec Tasks

These are the tasks to be completed for the spec detailed in @.agent-os/specs/2025-09-25-tracing-ai-dialog-ui/spec.md

> Created: 2025-09-25
> Status: Ready for Implementation

## Tasks

- [x] 1. Component Architecture and Base Classes
  - [x] 1.1 Write tests for component routing based on span.kind
  - [x] 1.2 Create SpanDetailBase shared component with common functionality
  - [x] 1.3 Implement component routing logic in main SpanDetail component
  - [x] 1.4 Add shared methods for JSON rendering and timestamp formatting
  - [x] 1.5 Verify component routing works for all span kinds
  - [x] 1.6 Verify all tests pass for base architecture

- [x] 2. Universal Span Overview Implementation
  - [x] 2.1 Write tests for universal span header rendering
  - [x] 2.2 Implement render_span_overview with trace ID, parent, timing
  - [x] 2.3 Add span hierarchy navigation and relationship display
  - [x] 2.4 Use consistent Preline UI classes for header styling
  - [x] 2.5 Verify overview displays correctly for all span types
  - [x] 2.6 Verify all tests pass for overview implementation

- [x] 3. Separate Component Files Implementation
  - [x] 3.1 Create tool_span_component.rb with function details, input/output visualization
  - [x] 3.2 Create agent_span_component.rb with agent info, model config, context display
  - [x] 3.3 Create llm_span_component.rb with request/response, token usage, cost metrics
  - [x] 3.4 Create handoff_span_component.rb with source/target agents, transfer data
  - [x] 3.5 Create guardrail_span_component.rb with filter results, security reasoning
  - [x] 3.6 Create pipeline_span_component.rb with stage execution, data flow
  - [x] 3.7 Create generic_span_component.rb for unknown span types
  - [x] 3.8 Write comprehensive tests for each separate component file
  - [ ] 3.9 Use consistent Preline UI classes across all separate components

- [x] 4. Stimulus Controller Implementation
  - [x] 4.1 Create span_detail_controller.js Stimulus controller
  - [x] 4.2 Implement toggleSection, toggleToolInput, toggleToolOutput actions
  - [x] 4.3 Add data-controller and data-action attributes to component templates
  - [x] 4.4 Write Stimulus controller tests for expand/collapse functionality
  - [x] 4.5 Test Stimulus functionality across different browsers
  - [x] 4.6 Ensure proper data-target attribute usage for section toggling
  - [x] 4.7 Verify all interactive elements work with Stimulus actions
  - [x] 4.8 Verify all Stimulus controller tests pass

- [x] 5. Integration and Polish
  - [x] 5.1 Write integration tests for complete span detail page display
  - [x] 5.2 Add timing information display (render_timing_details method)
  - [x] 5.3 Test responsive design on mobile, tablet, and desktop viewports
  - [x] 5.4 Optimize performance for spans with large attribute data
  - [x] 5.5 Update cross-references in spec.md to link all created files
  - [x] 5.6 Run complete test suite and ensure all existing functionality remains intact
  - [x] 5.7 Verify final implementation matches all spec requirements and design goals