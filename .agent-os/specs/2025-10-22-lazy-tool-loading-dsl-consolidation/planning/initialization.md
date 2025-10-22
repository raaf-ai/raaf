# Initial Spec Idea

## User's Initial Description

**Title:** Fix Tool Loading with Rails Eager Loading and Standardize Tool Definition DSL

**Description:**
Fix the issue where tools added via `uses_tool` are not loaded correctly when Rails eager loading is enabled in production/staging environments. The root cause is that tool class resolution happens at class definition time, before all classes are loaded.

Additionally, standardize tool definition in the DSL - currently there are multiple ways to define tools (`uses_tool`, `tool`, `uses_tools`, `uses_native_tool`) which is confusing. Consolidate to a single, clear approach.

**Key Problems:**
1. `uses_tool :tool_name` calls `RAAF::ToolRegistry.resolve()` during class definition
2. In eager-loaded environments, tool classes may not be loaded yet when agent classes load
3. `const_get` doesn't trigger autoloading when eager loading is enabled
4. Multiple tool definition methods create confusion and maintenance burden

**Solution Approach:**
1. Defer tool class resolution from class definition time to runtime (lazy loading)
2. Consolidate all tool definition methods into a single `tool` method
3. Remove backward compatibility aliases
4. Update documentation and examples

**No backward compatibility required** - this is a breaking change that will require users to update their code.

## Metadata
- Date Created: 2025-10-22
- Spec Name: lazy-tool-loading-dsl-consolidation
- Spec Path: .agent-os/specs/2025-10-22-lazy-tool-loading-dsl-consolidation
