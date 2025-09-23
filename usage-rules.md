# Bonfire.Common Usage Rules

Bonfire.Common is the foundational extension providing core utilities, helpers, and patterns used across all Bonfire extensions. These rules ensure consistent, safe, and idiomatic usage.

## Core Module Setup

Always use the provided module templates for consistency:

```elixir
# For general modules - provides Utils, Enums, Types, debug helpers
use Bonfire.Common

# For schemas with standardized behaviors
use Bonfire.Common.Schema

# For repos with extra functionality
use Bonfire.Common.Repo

# Just for the E module's data extraction
use Bonfire.Common.E
```

## Essential Utilities

### Safe Data Extraction with E

Use the `e/3` macro for safe nested data access with fallbacks:

```elixir
# Extract nested values safely
e(user, :profile, :name, "Anonymous")
e(data, [:deeply, :nested, :value], nil)

# Works with maps, structs, tuples, and Access behavior
settings = e(socket, :assigns, :current_user, :settings, %{})

# Use :nil! to raise on missing required associations
name = e(user, :profile, :name, :nil!)
```

### Type Checking and Conversion

Use Types module for comprehensive type operations:

```elixir
# Check types
Types.is_uid?(value)
Types.is_ulid?(id)  
Types.is_number?(input)

# Convert safely
Types.maybe_to_atom(string)
Types.maybe_to_integer(value, default)
Types.object_type(schema_or_object)

# UID operations
Types.uid(object)  # Extract ID from various sources
Types.uid!(object) # Raises if no ID found
```

### Enumerable Operations

Use Enums module for advanced operations:

```elixir
# Filter with multiple conditions
Enums.filter_empty(list, :skip_false)
Enums.filter_empty_enum(map, true) # For enumerables

# Advanced operations
Enums.map_tree(nested_data, &transform/1)
Enums.all_oks_or_error([{:ok, 1}, {:ok, 2}]) # {:ok, [1, 2]}
Enums.has_ok?([{:error, :e}, {:ok, :val}]) # true
```

## Error Handling Patterns

### Railway-Oriented Programming

Use the `~>` operator from Arrows for error tuple handling:

```elixir
with {:ok, user} <- find_user(id)
     ~> update_profile(params)
     ~> send_notification() do
  {:ok, user}
end
```

### Transactional Operations

Use `transact_with` for operations that should be atomic:

```elixir
repo().transact_with(fn ->
  with {:ok, user} <- create_user(attrs),
       {:ok, profile} <- create_profile(user) do
    {:ok, {user, profile}}
  else
    error -> error  # Will rollback
  end
end)
```

### Debug Helpers

Use debug utilities appropriately:

```elixir
# Development debugging (uses Untangle)
debug(value, "Processing user")
info(data, "API Response")
warn(result, "Unexpected value")  
error(exception, "Failed to process")

# Production-safe debugging
maybe_debug(result, socket, "Component rendered")
```

## Configuration Access

### Runtime Configuration

Access configuration consistently:

```elixir
# Get config with fallback
Config.get(:feature_flag, false)
Config.get([:bonfire, :ui, :theme], "default")

# Extension-specific config
Config.get_ext(:bonfire_me, :profile_fields, [])
```

### Module Configuration

Retrieve module configurations:

```elixir
# Get module config by key 
config = Config.for_module(Bonfire.Common)

# Get extension config  
ext_config = Config.for_extension(:bonfire_social)
```

## URL and Path Generation

Use URIs module for consistent URL handling:

```elixir
# Generate paths
URIs.path(user)           # /user/123
URIs.path(user, :profile) # /user/123/profile

# Full URLs
URIs.canonical_url("/posts/#{id}")

# Query parameters
URIs.query_add(url, page: 2, filter: "active")
```

## User and Account Utilities

Access user data consistently:

```elixir
# Get current user/account
current_user = Utils.current_user(socket_or_assigns)
current_account = Utils.current_account(context)
current_user_id = Utils.current_user_id(socket_or_assigns)

# Get from various contexts
Utils.current_user(%{current_user: user})
Utils.current_user(%{assigns: %{current_user: user}})
Utils.current_user([current_user: user])

# Check module availability
if Utils.module_enabled?(Bonfire.Social) do
  # Use social features
end
```

## Async Operations

Handle async operations properly:

```elixir
# Run in background (uses Oban if available)
Utils.maybe_apply_async(Module, :function, [args])

# Apply with fallback
Utils.maybe_apply(Module, :function, [args], fallback_return: nil)

# Debounced operations (not yet implemented)
Utils.debounce_apply(key, 1000, fn -> expensive_op() end)
```

## PubSub Integration

Use the PubSub system for real-time updates:

```elixir
# Subscribe to topics
PubSub.subscribe(topic, socket)
PubSub.subscribe("feed:#{user_id}", socket)

# Broadcast messages
PubSub.broadcast(topic, message)
PubSub.broadcast(user_ids, {Module, :event_name, data})
```

## Repository Patterns

### Query Helpers

Use repo helpers for common patterns:

```elixir
# Get single result
repo().single(query)  # Returns single result or raises
repo().one(query)     # Returns {:ok, result} or {:error, :not_found}

# Preload associations
repo().maybe_preload(object, [:profile, :settings])
repo().preload_all(objects, associations)

# Insert operations
repo().put(changeset)  # With error mapping
repo().insert_all_or_error(schema, entries)
```

### Needles/Pointers System

Work with the unified object system:

```elixir
# Find any object by ULID
{:ok, object} = Needles.get(ulid, current_user: user)
Needles.get!(ulid, opts)  # Raises on not found

# Get with specific opts
Needles.one(id, skip_boundary_check: true)

# Follow pointers to their target
followed = Needles.follow!(pointer)

# Get table info
Needles.table_schema(object)
Needles.table_id(object)
```

## Caching

Use the built-in caching system:

```elixir
# Basic caching
Cache.put("key", value, ttl: 3600)
{:ok, value} = Cache.get("key")
Cache.delete("key")

# Function result caching
Cache.maybe_apply_cached(&expensive_function/2, [arg1, arg2], 
  cache_key: "custom_key",
  ttl: 3600
)
```

## Text Processing

Handle text manipulation safely:

```elixir
# Markdown processing
Text.maybe_markdown_to_html(content, opts)

# URL/mention normalization
Text.normalise_links(text, :markdown)
Text.normalise_mentions(text)

# Utilities
Text.slug("Hello World!") # "hello-world"
Text.random_string(length: 16)
Text.underscore_truncate("long_name_here", 10) # "long_name"
```

## Media Handling

Work with user media consistently:

```elixir
# Get media URLs
Media.avatar_url(user)
Media.banner_url(user)
Media.image_url(object)

# Process uploads
Media.save(upload, user)
```

## Testing Patterns

Include doctests for pure functions:

```elixir
@doc """
Converts a value to an integer safely.

## Examples

    iex> maybe_to_integer("42")
    42

    iex> maybe_to_integer("invalid", 0)  
    0
"""
def maybe_to_integer(val, default \\ nil)
```

Use DataCase for tests:

```elixir
use Bonfire.Common.DataCase

test "example" do
  # Provides repo(), current_user(), etc.
end
```

## Common Anti-Patterns to Avoid

### ❌ Direct Map Access
```elixir
# Bad
user.profile.name  # Can raise if nil

# Good  
e(user, :profile, :name, "Anonymous")
```

### ❌ Unchecked Type Conversions
```elixir
# Bad
String.to_atom(user_input)  # Security risk

# Good
Types.maybe_to_atom(input)  # Safe with validation
```

### ❌ Hardcoded Configuration
```elixir
# Bad
@page_size 20

# Good
Config.get(:page_size, 20)
```

### ❌ Manual URL Building
```elixir
# Bad  
"/user/#{user.id}/profile"

# Good
URIs.path(user, :profile)
```

### ❌ Direct Repo Calls in Modules
```elixir
# Bad
Repo.get(User, id)

# Good
repo().one(from u in User, where: u.id == ^id)
```

## Security Considerations

- Never use `String.to_atom/1` on user input - use `Types.maybe_to_atom/1`
- Validate UIDs/ULIDs with `Types.is_uid?/1` before database operations
- Use `Text.normalise_mentions/1` for safe mention parsing
- Apply `Types.maybe_to_atom/1` only on known safe values
- Check boundaries with `skip_boundary_check: true` only when absolutely necessary

## Performance Tips

- Use `e/3` macro for compile-time optimized paths when possible
- Cache expensive operations with `Cache` module
- Preload associations with `repo().maybe_preload/2` to avoid N+1 queries
- Use `Enums.map_optimize/2` for large collections
- Batch operations with `repo().insert_all_or_error/2`

## Module Organization

Structure extensions consistently:

```
bonfire_extension/
├── lib/
│   ├── context_modules/     # Business logic (plural names)
│   ├── schemas/             # Ecto schemas (singular names)  
│   ├── runtime_config.ex    # Runtime configuration
│   └── my_extension.ex      # Main module
└── usage-rules.md           # Usage documentation
```

## Documentation Standards

Document all public functions:

```elixir
@doc """
Short description of what the function does.

## Parameters
- `user` - The user struct or ID
- `opts` - Options keyword list
  - `:preload` - Associations to preload (default: [])

## Examples
    
    iex> get_user("123", preload: [:profile])
    %User{id: "123", profile: %Profile{}}
"""
```

## Extension Integration

When building extensions:

```elixir
defmodule MyExtension do
  use Bonfire.Common.ExtensionModule
  
  # Declares extension capabilities
  declare_extension("My Extension",
    icon: "hero-puzzle-piece",
    description: "Does amazing things"
  )
end
```

## Debugging and Development

### Console Helpers

Available in IEx:

```elixir
# Run as different user
Bonfire.Common.Simulation.simulate_user_session("username")

# Memory profiling
Bonfire.Common.MemoryMonitor.start()
```

### Telemetry Integration

Monitor performance:

```elixir
:telemetry.execute(
  [:bonfire, :my_extension, :operation],
  %{duration: duration},
  %{user_id: user_id}
)
```