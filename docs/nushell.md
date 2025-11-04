# Nushell Development Guide

This guide covers essential Nushell patterns, common pitfalls, and best practices for working with Nushell scripts in this project.

## Critical Differences from Bash/POSIX Shells

### 1. Main Function Auto-Execution
**CRITICAL**: When a script defines a `main` function, Nushell **automatically calls it** when the script is executed directly.

```nu
# ❌ WRONG - causes double execution
def main [] {
    print "hello"
}
main  # Don't do this!

# ✅ CORRECT - main is called automatically
def main [] {
    print "hello"
}
```

### 2. Everything is Structured Data
- Nushell works with structured data (tables, records, lists), not just strings
- Pipelines pass structured data between commands
- Use `| describe` to check data types

```nu
# Data flows as structured objects
ls | where size > 1kb | get name
```

### 3. Variables and Mutability
```nu
let x = 5          # immutable (default)
mut y = 10         # mutable
$y = 15            # update mutable variable
const Z = 20       # compile-time constant
```

## Function Definitions

### Basic Syntax
```nu
def function-name [param1: type, param2: type = default] {
    # function body
    $param1  # last expression is return value
}

# With flags
def main [
    --flag (-f): bool      # boolean flag
    --value (-v): int = 5  # flag with default
    ...args: list<string>  # variadic args
] {
    # body
}
```

### Return Values
```nu
# ✅ Return last expression
def add [a: int, b: int] {
    $a + $b  # implicit return
}

# ✅ Early return
def check [x: int] {
    if $x < 0 { return "negative" }
    "positive"
}
```

## Data Types

### Common Types
- `int`, `float`, `string`, `bool`
- `list<T>`, `record`, `table`
- `path`, `duration`, `filesize`
- `any` for dynamic types

### Type Checking
```nu
$var | describe        # get type as string

# ❌ WRONG - too strict, fails for list<string>, list<int>, etc.
($var | describe) == "list<any>"

# ✅ CORRECT - works for all list types
($var | describe | str starts-with "list<")
```

## Pipelines and Data Flow

### Pipeline Operators
```nu
| each {|item| ... }    # iterate over items
| where condition       # filter items
| get field            # extract field
| select col1 col2     # select columns
| reduce {|item, acc| ... }  # fold/reduce - item first, accumulator second!
```

### CRITICAL: Reduce Parameter Order
```nu
# ❌ WRONG - parameters are backwards!
["a", "b", "c"] | reduce -f [] {|acc, item| 
    $acc | append $item
}
# Returns: "c" (last item, not accumulated list)

# ✅ CORRECT - item comes FIRST, accumulator SECOND
["a", "b", "c"] | reduce -f [] {|item, acc| 
    $acc | append $item
}
# Returns: ["a", "b", "c"] (properly accumulated)
```

**Remember**: In Nushell's `reduce`, the closure parameters are `{|current_item, accumulator|` not `{|accumulator, current_item|` like in some other languages!

### Common Patterns
```nu
# Check if empty
if ($list | is-empty) { ... }

# Length
$list | length

# Append/prepend
$list | append $new_item
$list | prepend $new_item

# Filter and transform
$list | where {|x| $x > 5 } | each {|x| $x * 2 }
```

## Error Handling

### Try-Catch Blocks
```nu
# Basic try-catch
try {
    # risky operation
} catch {
    # handle error
    []  # return default value
}

# Capture error
try {
    some-command
} catch { |err|
    print $"Error: ($err)"
}
```

### Error Propagation
```nu
# Use '?' to propagate errors (newer Nushell)
let result = (some-command)? 

# Or use try with early return
def safe-operation [] {
    let result = (try { risky-op } catch { return null })
    $result
}
```

## String Interpolation

```nu
# ✅ CORRECT - String interpolation with $"..."
let name = "world"
print $"Hello ($name)!"

# Nested expressions
print $"Result: ($x + $y)"

# Multi-line
print $"
Line 1: ($var1)
Line 2: ($var2)
"

# ❌ WRONG - This prints literal "$name"!
print $"Hello $name!"        # Output: "Hello $name!"
print $"$name is here"       # Output: "$name is here"

# ✅ CORRECT - Always use parentheses for variable interpolation
print $"Hello ($name)!"      # Output: "Hello world!"
print $"($name) is here"     # Output: "world is here"
```

**Critical**: In Nushell string interpolation, you MUST use `($variable)` syntax, not just `$variable`. The `$variable` without parentheses is treated as literal text!

### Escaping Parentheses in Interpolated Strings
```nu
# ❌ WRONG - parentheses are interpreted as command execution
print $"Total: ($count) service(s)"  # Error: command 's' not found!

# ✅ CORRECT - escape literal parentheses with backslash
print $"Total: ($count) service\(s\)"  # Output: "Total: 3 service(s)"

# ✅ ALTERNATIVE - use regular string concatenation
print $"Total: ($count) services"     # Output: "Total: 3 services"
```

**Key Insight**: In interpolated strings (`$"..."`), parentheses have special meaning for variable interpolation. To use literal parentheses in the text, escape them with `\(` and `\)`.

## Control Flow

### If-Else
```nu
if $condition {
    # true branch
} else if $other {
    # else if branch
} else {
    # else branch
}

# Inline
let x = (if $cond { 5 } else { 10 })
```

### Loops
```nu
# For loop
for item in $list {
    print $item
}

# While loop
while $condition {
    # body
}

# Loop with index
$list | enumerate | each {|item|
    print $"($item.index): ($item.item)"
}
```

## File Operations

### Path Handling
```nu
# Path operations
"dir/file.txt" | path exists
"file.txt" | path expand  # resolve to absolute
"a/b/c" | path join "file.txt"
"/path/to/file.txt" | path basename
"/path/to/file.txt" | path dirname
```

### File I/O
```nu
# Read file - auto-detects format by extension
open file.txt           # opens as string
open file.json          # auto-parses as JSON
open file.nuon          # auto-parses as NUON
open config.toml        # auto-parses as TOML

# ❌ WRONG - redundant, open already parsed it!
open file.json | from json
open file.nuon | from nuon

# ✅ CORRECT - open handles it automatically
open file.json
open file.nuon

# Write file
"content" | save file.txt
{name: "value"} | to json | save file.json
{name: "value"} | to nuon | save file.nuon

# List directory
ls
ls *.nu
glob "**/*.nu"  # recursive glob
```

## Common Pitfalls

### 1. List Operations
```nu
# ❌ WRONG - trying to modify immutable list
let list = [1, 2, 3]
$list = ($list | append 4)  # Error!

# ✅ CORRECT - use mut or reassign
mut list = [1, 2, 3]
$list = ($list | append 4)

# Or with let
let list = [1, 2, 3]
let list = ($list | append 4)  # shadowing
```

### 2. Empty Checks
```nu
# ✅ Use is-empty for collections
if ($list | is-empty) { ... }

# ❌ Don't use length == 0 (less idiomatic)
if ($list | length) == 0 { ... }
```

### 3. String vs Path
```nu
# Paths are a distinct type
let p = "/some/path"  # this is a string
let p = ("/some/path" | path expand)  # this is path-like

# Path operations work on both, but be consistent
```

### 4. Command vs Expression Context
```nu
# In command context (after |)
ls | where size > 1kb

# In expression context (in assignments)
let files = (ls | where size > 1kb)
```

### 5. Accessing Record Fields Safely
```nu
# ❌ WRONG - crashes if field doesn't exist
let value = ($record.field | default "fallback")

# ✅ CORRECT - safe field access with try-catch
let value = (try { $record.field } catch { "fallback" })

# ✅ ALSO CORRECT - with default
let value = (try { $record.field } catch { "fallback" } | default "fallback")

# Example: accessing optional config fields
let cfg = {enabled: true}  # missing 'name' field
let name = (try { $cfg.name } catch { "default-name" })  # works!
let enabled = (try { $cfg.enabled } catch { false })     # returns true
```

### 5b. Modifying Record Fields: `insert` vs `upsert`
```nu
# ❌ WRONG - insert fails if field already exists!
mut record = {name: "Alice", age: 30}
$record = ($record | insert age 31)  # Error: Column 'age' already exists

# ✅ CORRECT - upsert updates existing or inserts new
mut record = {name: "Alice", age: 30}
$record = ($record | upsert age 31)     # Works! Updates age to 31
$record = ($record | upsert city "NYC") # Works! Adds new field

# When merging records, always use upsert
for key in ($overrides | columns) {
  let value = ($overrides | get $key)
  $result = ($result | upsert $key $value)  # Safe for existing or new fields
}
```

**Key Insight**: Use `insert` only when you're certain the field doesn't exist. Use `upsert` when you want to update-or-insert behavior (like `INSERT ... ON CONFLICT UPDATE` in SQL).

### 6. Let Binding and Piping
```nu
# ❌ WRONG - let returns nothing, can't pipe it!
let result = (let data = [1, 2, 3]
    | if ($condition) { $in } else { $in | where {|x| $x > 1 } })
# result is nothing/null!

# ✅ CORRECT - assign first, then use
let data = [1, 2, 3]
let result = (if ($condition) { 
    $data 
} else { 
    $data | where {|x| $x > 1 }
})

# Alternative: use parentheses to group the expression properly
let result = (
    let data = [1, 2, 3];
    if ($condition) { $data } else { $data | where {|x| $x > 1 } }
)
```

**Key Insight**: The `let` statement doesn't produce a value - it's a binding, not an expression. You can't pipe from a `let` statement. Always separate your data creation from your data transformation.

## Module System

### Using Modules
```nu
# Import all exports
use module.nu *

# Import specific items
use module.nu [func1, func2]

# Use without importing
source module.nu
```

### Exporting
```nu
# In module.nu
export def public-func [] { ... }
export-env { $env.VAR = "value" }

def private-func [] { ... }  # not exported

# Export main function to make it callable from other scripts
export def main [--flag: bool] {
    # This allows other scripts to import and call this function
}
```

### Calling Module Functions
```nu
# Import and call exported functions
use module.nu

# If main is exported, call it directly (not "module main")
module --flag

# Call other exported functions
module public-func

# ❌ WRONG - don't specify "main" when calling
module main --flag  # Error: extra positional argument

# ✅ CORRECT - module name calls its exported main
module --flag
```

## Passing Complex Data Between Scripts

### Problem: Command-Line Arguments Don't Handle Lists Well
```nu
# ❌ WRONG - passing lists via command line is painful!
let sans = ["DNS:host1", "DNS:host2"]
nu script.nu --san ($sans | to nuon)  # Parsing nightmare!
```

### Solution: Use Module Imports
```nu
# In generate-cert.nu
export def main [--san: list<string> = []] {
    # Can receive lists directly!
}

# In caller script
use ./generate-cert.nu
generate-cert --san ["DNS:host1", "DNS:host2"]  # Clean!
```

**Key Insight**: When you need to pass complex data (lists, records, tables) between scripts:
1. Refactor the target script to `export def main`
2. Import it as a module
3. Call the function directly with native Nushell data types

This avoids string serialization/parsing issues entirely!

## Best Practices

1. **Always use `def main` for script entry points** - don't call it explicitly
2. **Use structured data** - avoid string parsing when possible
3. **Type your function parameters** - helps catch errors early
4. **Use `try-catch` for fallible operations** - especially file I/O and external commands
5. **Prefer `each` over loops** - more idiomatic and pipeline-friendly
6. **Use `describe` when debugging** - understand what data types you're working with
7. **Handle empty cases** - always check if lists/tables are empty before processing
8. **Use `try-catch` for safe record field access** - `try { $record.field } catch { default }`
9. **Export main functions from reusable scripts** - allows direct function calls with complex data
10. **Check list types with `str starts-with "list<"`** - not exact equality
11. **Always use parentheses in string interpolation** - `$"($var)"` not `$"$var"`
12. **Escape literal parentheses in interpolated strings** - `$"text\(s\)"` not `$"text(s)"`
13. **Remember reduce parameter order** - `{|item, accumulator|` not `{|accumulator, item|`
14. **Don't pipe from let statements** - `let` is a binding, not an expression that produces a value
15. **Use `upsert` for safe record updates** - use `insert` only when field definitely doesn't exist

## Command Execution

### Running External Commands
```nu
# Simple execution
git status

# Capture output
let output = (git status | complete)

# With string interpolation
git commit -m $"Message: ($var)"

# Ignore errors
rm -f file.txt | ignore
```

## Debugging

```nu
# Print for debugging
print $variable
print $"Debug: ($variable)"

# Inspect type
$variable | describe

# Inspect structure
$variable | table
$variable | to json

# Debug pipeline
$data | debug  # shows data at this point in pipeline
```

### Common Debugging Scenarios

#### Script runs twice?
```nu
# Check for explicit main call at end of file
# ❌ This causes double execution:
def main [] { ... }
main  # Remove this line!
```

#### "Cannot find column" error?
```nu
# The record field doesn't exist or record is empty
# Use try-catch for safe access:
let value = (try { $record.field } catch { default_value })
```

#### Type mismatch with lists?
```nu
# Check if you're doing exact type matching
# ❌ ($list | describe) == "list<any>"
# ✅ ($list | describe | str starts-with "list<")
```

#### File parsing fails?
```nu
# Don't double-parse files
# ❌ open file.nuon | from nuon
# ✅ open file.nuon  # Already parsed!
```

#### Reduce returns wrong value?
```nu
# Check parameter order - item comes first!
# ❌ ["a", "b", "c"] | reduce -f [] {|acc, item| $acc | append $item }
# ✅ ["a", "b", "c"] | reduce -f [] {|item, acc| $acc | append $item }
```

#### Variable shows literal "$name" in output?
```nu
# String interpolation requires parentheses
# ❌ print $"Hello $name"  # prints: "Hello $name"
# ✅ print $"Hello ($name)"  # prints: "Hello world"
```

#### Error: "command 's' not found" in string?
```nu
# Unescaped parentheses in interpolated strings are interpreted as commands
# ❌ print $"Total: ($count) service(s)"  # Error: command 's' not found
# ✅ print $"Total: ($count) service\(s\)"  # Escape literal parens
```

#### Error: "Column already exists"?
```nu
# You're trying to insert into an existing field
# ❌ $record | insert field_name new_value  # Fails if field exists
# ✅ $record | upsert field_name new_value  # Updates or inserts
```

#### Variable is nothing/null unexpectedly?
```nu
# Check if you're piping from a let statement
# ❌ let x = (let data = [1, 2] | where ...)  # x is nothing!
# ✅ let data = [1, 2]; let x = ($data | where ...)
```

## Version-Specific Notes

- Some features (like `?` operator) require newer Nushell versions
- Use `version` command to check Nushell version
- This guide assumes Nushell 0.80+ (check compatibility if using older versions)

## Quick Reference: Data Type Conversions

```nu
# To string
$value | to text
$value | into string

# To int
"123" | into int

# To list
"a,b,c" | split row ","

# To record/table
[[name age]; [Alice 30] [Bob 25]]  # table literal
{name: "Alice", age: 30}  # record literal
```

