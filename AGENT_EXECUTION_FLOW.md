# RAAF Agent Execution Flow Documentation

This document contains comprehensive Mermaid diagrams showing the complete flow from agent call to result in the RAAF (Ruby AI Agents Factory) framework.

## 1. High-Level Agent Execution Flow

```mermaid
graph TB
    A[Agent.call with params] --> B[Build Context]
    B --> C[Create RAAF Runner]
    C --> D[Execute Agent]
    D --> E[Process AI Response]
    E --> F[Return Result]
    
    B --> B1[Phase 1: Static Context]
    B --> B2[Phase 2: Computed Context]
    B1 --> B2
    
    D --> D1[Send to OpenAI API]
    D1 --> D2[Handle Tool Calls]
    D2 --> D3[Process Response]
    
    style B fill:#e1f5fe
    style D fill:#fff3e0
    style F fill:#e8f5e8
```

## 2. Detailed Context Building Flow

```mermaid
graph TD
    A["Agent.call params: hash"] --> B["build_auto_context"]
    
    B --> C["Phase 1: Static Context Building"]
    C --> C1["Create ContextBuilder"]
    C1 --> C2["Apply exclusion rules"]
    C2 --> C3["Process each param"]
    C3 --> C4["Check for prepare_key_for_context methods"]
    C4 --> C5["builder.with key, value"]
    C5 --> C6["Apply default values from rules"]
    C6 --> C7["builder.current_context"]
    C7 --> C8["context = static context copy"]
    
    C8 --> D["Phase 2: Computed Context"]
    D --> D1["Find build_*_context methods via reflection"]
    D1 --> D2["For each build method..."]
    D2 --> D3["method = build_existing_icps_context"]
    D3 --> D4["Check if context.has? key"]
    D4 --> D5{"Already exists?"}
    
    D5 -->|Yes| D6["Return existing value"]
    D5 -->|No| D7["Call compute method"]
    D7 --> D8["compute_existing_icps"]
    D8 --> D9["Access context.get :product"]
    D9 --> D10["Access context.get :company"]
    D10 --> D11["Generate computed value"]
    D11 --> D12["builder.with computed_key, value"]
    
    D6 --> D13["builder.build - Final Context"]
    D12 --> D13
    D13 --> E["Return ContextVariables instance"]
    
    style C fill:#e3f2fd
    style D fill:#fff8e1
    style C8 fill:#c8e6c9
    style D9 fill:#ffcdd2
    style D10 fill:#ffcdd2
```

## 3. RAAF Runner Execution Flow

```mermaid
sequenceDiagram
    participant Client
    participant Agent
    participant ContextBuilder
    participant Runner
    participant Provider
    participant OpenAI
    participant Tools
    
    Client->>Agent: call(params)
    Agent->>ContextBuilder: build_auto_context(params)
    
    Note over ContextBuilder: Phase 1: Static Context
    ContextBuilder->>ContextBuilder: Process params + defaults
    ContextBuilder->>ContextBuilder: current_context (copy)
    
    Note over ContextBuilder: Phase 2: Computed Context  
    ContextBuilder->>Agent: build_existing_icps_context
    Agent->>Agent: context.get(:product)
    Agent->>Agent: context.get(:company)
    Agent->>Agent: compute_existing_icps
    Agent-->>ContextBuilder: computed values
    
    ContextBuilder-->>Agent: final ContextVariables
    
    Agent->>Runner: new(agent: self, context: context)
    Agent->>Runner: run(message)
    
    Runner->>Provider: create_chat_completion
    Provider->>OpenAI: POST /v1/chat/completions
    
    alt Tool calls required
        OpenAI-->>Provider: response with tool_calls
        Provider-->>Runner: tool calls needed
        Runner->>Tools: execute_tool(name, args)
        Tools-->>Runner: tool results
        Runner->>Provider: continue with tool results
        Provider->>OpenAI: POST /v1/chat/completions (with tool results)
    end
    
    OpenAI-->>Provider: final response
    Provider-->>Runner: assistant message
    Runner-->>Agent: execution result
    Agent-->>Client: final result
```

## 4. Context Variable Access Pattern

```mermaid
graph LR
    subgraph "Agent Instance"
        A["Agent.call"] --> B["build_auto_context"]
        B --> C["context instance variable"]
    end
    
    subgraph "ContextBuilder"
        D["ContextBuilder.new"] --> E["Internal context ContextVariables"]
        E --> F["builder.with adds to internal context"]
        F --> G["builder.current_context"]
        G --> H["Returns COPY of context"]
    end
    
    subgraph "Build Methods Access"
        I["build_existing_icps_context"] --> J["context.get :product"]
        J --> K["context.get :company"]  
        K --> L["compute_existing_icps"]
        L --> M["Generated value"]
    end
    
    B --> D
    H --> C
    C --> I
    M --> N["builder.with computed_key, value"]
    N --> O["builder.build final context"]
    
    style H fill:#c8e6c9
    style C fill:#c8e6c9
    style J fill:#ffcdd2
    style K fill:#ffcdd2
```

## 5. OpenAI API Interaction Flow

```mermaid
graph TD
    A[Runner.run message] --> B[Prepare conversation history]
    B --> C[Build system prompt from instructions]
    C --> D[Add tools/functions to payload]
    D --> E[Send to OpenAI API]
    
    E --> F{Response type?}
    F -->|Assistant message| G[Extract content]
    F -->|Tool calls| H[Process tool calls]
    
    H --> I[For each tool call...]
    I --> J[Extract tool name & arguments]
    J --> K{Tool type?}
    
    K -->|Built-in tool| L[Execute built-in tool]
    K -->|Custom tool| M[Execute custom tool method]
    K -->|Handoff tool| N[Transfer to another agent]
    
    L --> O[Format tool result]
    M --> O
    N --> P[Continue with target agent]
    
    O --> Q[Add tool result to conversation]
    Q --> R[Send updated conversation to API]
    R --> F
    
    G --> S[Return final result]
    P --> S
    
    style E fill:#fff3e0
    style H fill:#e1f5fe
    style S fill:#e8f5e8
```

## 6. Tool Execution Detail

```mermaid
sequenceDiagram
    participant OpenAI
    participant Runner
    participant ToolRegistry
    participant CustomTool
    participant HandoffAgent
    
    OpenAI->>Runner: tool_calls: [{"name": "web_search", "arguments": {"query": "Ruby"}}]
    
    Runner->>Runner: parse tool calls from response
    
    loop For each tool call
        Runner->>ToolRegistry: find_tool("web_search")
        ToolRegistry-->>Runner: tool definition
        
        alt Built-in Tool
            Runner->>Runner: execute built-in tool
            Runner->>Runner: format_tool_result
        else Custom Tool Method
            Runner->>CustomTool: call method with arguments  
            CustomTool-->>Runner: tool result
        else Handoff Tool
            Runner->>HandoffAgent: transfer_to_agent
            HandoffAgent-->>Runner: handoff result
        end
        
        Runner->>Runner: add tool result to conversation
    end
    
    Runner->>OpenAI: POST with updated conversation + tool results
    OpenAI-->>Runner: final assistant response
```

## 7. Error Handling and Recovery Flow

```mermaid
graph TD
    A[Agent Execution] --> B{Error Occurred?}
    B -->|No| C[Success Path]
    B -->|Yes| D[Error Type Analysis]
    
    D --> E{Context Building Error?}
    D --> F{API Error?}
    D --> G{Tool Execution Error?}
    D --> H{Validation Error?}
    
    E -->|Missing Context| I[Log missing context keys]
    E -->|Invalid Context| J[Log validation failure]
    
    F -->|Rate Limit| K[Retry with backoff]
    F -->|API Error| L[Log API error details]
    
    G -->|Tool Failed| M[Return error to AI]
    G -->|Tool Missing| N[Log missing tool]
    
    H -->|Schema Error| O[Log schema validation]
    H -->|Type Error| P[Log type mismatch]
    
    I --> Q[Return Error Result]
    J --> Q
    L --> Q
    M --> R[Continue with error context]
    N --> Q
    O --> Q
    P --> Q
    
    K --> S[Retry Execution]
    S --> A
    
    R --> T[AI handles tool error]
    T --> U[Continue execution]
    
    style Q fill:#ffcdd2
    style C fill:#c8e6c9
    style K fill:#fff3e0
```

## 8. Memory and State Management

```mermaid
graph LR
    subgraph "Agent Instance State"
        A["context - Current context"]
        B["agent_config - Class configuration"]
        C["tools - Available tools"]
    end
    
    subgraph "ContextVariables (Immutable)"
        D["Internal hash storage"]
        E["get/set/has? methods"]
        F["Each set() returns NEW instance"]
    end
    
    subgraph "Builder State (Mutable)"
        G["Accumulates changes"]
        H["builder.with() modifies internal state"]
        I["builder.build() creates final ContextVariables"]
    end
    
    A --> D
    D --> E
    E --> J["Context Readers: product, company"]
    
    G --> H
    H --> I
    I --> D
    
    J --> K["build_*_context methods"]
    K --> L["compute_existing_icps"]
    L --> M["Generated computed values"]
    M --> H
    
    style F fill:#c8e6c9
    style A fill:#e1f5fe
    style M fill:#fff3e0
```

## Key Implementation Details

### Two-Phase Context Building

The most critical aspect of the RAAF context system is the **two-phase context building** approach:

1. **Phase 1: Static Context** - Parameters and defaults are processed first
2. **Phase 2: Computed Context** - `@context` is made available with static values, then computed methods can safely access them

This resolves timing issues where `build_*_context` methods couldn't access static context variables like `product` and `company`.

### Immutable Context Pattern

RAAF uses an immutable context pattern where:
- Each `ContextVariables.set()` call returns a **new instance**
- The `ContextBuilder` accumulates changes in mutable state
- `builder.current_context()` returns a **copy** for safe access
- Final `builder.build()` creates the complete immutable context

### Error Recovery Strategies

The framework includes comprehensive error handling:
- **Context errors** are logged with missing key details
- **API errors** include retry logic with exponential backoff  
- **Tool errors** are passed back to the AI for handling
- **Validation errors** provide detailed schema information

### Tool Execution Model

RAAF supports multiple tool types:
- **Built-in tools** (web search, file operations)
- **Custom tool methods** defined on the agent
- **Handoff tools** for multi-agent workflows
- **OpenAI-hosted tools** for complex operations

Each tool type follows the same execution pattern but with different resolution and execution strategies.

---

*Generated: 2025-08-15*
*Framework: RAAF (Ruby AI Agents Factory)*
*Version: Current as of commit 6bcdd3c*