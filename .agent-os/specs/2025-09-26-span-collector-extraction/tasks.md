# Spec Tasks

These are the tasks to be completed for the spec detailed in @.agent-os/specs/2025-09-26-span-collector-extraction/spec.md

> Created: 2025-09-26
> Status: Ready for Implementation

## Tasks

- [x] 1. Create Collector Infrastructure
  - [x] 1.1 Write tests for BaseCollector simplified DSL (span and result methods)
  - [x] 1.2 Implement BaseCollector with simplified DSL and lambda execution
  - [x] 1.3 Write tests for component_prefix generation and safe_value helper
  - [x] 1.4 Write tests for naming-based collector discovery logic
  - [x] 1.5 Implement naming-based discovery with Core/DSL agent handling
  - [x] 1.6 Verify all infrastructure tests pass

- [x] 2. Implement Component-Specific Collectors
  - [x] 2.1 Write tests for AgentCollector (Core Agent) simplified DSL usage and data extraction
  - [x] 2.2 Implement AgentCollector using simplified DSL for core agents
  - [x] 2.3 Write tests for DslAgentCollector (DSL Agent) with DSL-specific fields
  - [x] 2.4 Implement DslAgentCollector using simplified DSL for DSL agents
  - [x] 2.5 Write tests for ToolCollector simplified DSL usage and data extraction
  - [x] 2.6 Implement ToolCollector using simplified DSL with agent context detection
  - [x] 2.7 Write tests for PipelineCollector simplified DSL usage and data extraction
  - [x] 2.8 Implement PipelineCollector using simplified DSL for flow structure collection
  - [x] 2.9 Write tests for JobCollector simplified DSL usage and data extraction
  - [x] 2.10 Implement JobCollector using simplified DSL for ActiveJob integration
  - [x] 2.11 Verify all collector tests pass

- [x] 3. Integrate Collectors with Traceable Module
  - [x] 3.1 Write tests for Traceable module collector delegation
  - [x] 3.2 Update Traceable module to use naming-based discovery for data collection
  - [x] 3.3 Write integration tests ensuring identical span data output
  - [x] 3.4 Verify existing span tests still pass with collector system
  - [x] 3.5 Verify all integration tests pass

- [x] 4. Remove Collection Methods from Business Classes
  - [x] 4.1 Write tests confirming methods are removed from Agent classes
  - [x] 4.2 Remove collect_span_attributes from Agent and DSL::Agent
  - [x] 4.3 Remove collect_result_attributes from Agent classes
  - [x] 4.4 Write tests confirming methods are removed from Pipeline classes
  - [x] 4.5 Remove collection methods from Pipeline classes
  - [x] 4.6 Remove any remaining collection methods from other traceable classes
  - [x] 4.7 Verify all tests pass after method removal

- [x] 5. Comprehensive Testing and Validation
  - [x] 5.1 Run complete test suite to ensure no regressions
  - [x] 5.2 Test span data collection with real components in various scenarios
  - [x] 5.3 Verify thread safety of collector system
  - [x] 5.4 Performance test collector overhead compared to previous implementation
  - [x] 5.5 Verify all tests pass and no functionality is broken