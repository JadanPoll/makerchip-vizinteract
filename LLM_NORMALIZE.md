# TL-Verilog / M5 / TL-X / Visual Debug — Hypercomprehensive LLM Cheatsheet

> **Purpose:** This document is the complete reference for an LLM to write correct code using M5, TL-X (TL-Verilog), and the Visual Debug (VIZ) framework. Every syntax rule, macro, behavior, gotcha, and edge case documented in the official specifications is captured here. Do not guess; use this document.

---

## Table of Contents

1. [M5 Macro Preprocessor — Full Reference](#1-m5-macro-preprocessor--full-reference)
2. [TL-X / TL-Verilog Language Syntax](#2-tl-x--tl-verilog-language-syntax)
3. [TL-Verilog Macro Preprocessing Integration](#3-tl-verilog-macro-preprocessing-integration)
4. [Visual Debug (VIZ) API](#4-visual-debug-viz-api)
5. [Critical Gotchas & Common Mistakes](#5-critical-gotchas--common-mistakes)

---

## 1. M5 Macro Preprocessor — Full Reference

### 1.1 What is M5?

M5 is a macro preprocessor built on top of GNU M4. It adds programming-language-like features: named variables, scoped functions, code blocks, loops, conditionals, string operations, and a debug framework. It is primarily used with TL-Verilog but works with any text format.

**Processing pipeline (in order):**
1. Substitute quotes for single control characters.
2. Process syntactic sugar in a single pre-pass (strip comments, process blocks/labels, check pragmas).
3. Write the resulting file.
4. Run M4 on that file (macro substitution).

**Key configurations (fixed, not user-changeable):**
- Builtin macro prefix: `m4_` (internal only; do not use directly)
- Quote open: `['`
- Quote close: `']`

---

### 1.2 Quotes

| Syntax | Meaning |
|--------|---------|
| `['…']` | Literal quoted text — no macro substitution or comma interpretation inside |
| `['']` | Empty quote — used as a word boundary |

**Rules:**
- Quotes prevent substitution. Use them to include commas, parentheses, or `m5_`-prefixed text in literal output.
- The end quote `']` acts as a word boundary — text immediately following resumes normal processing.
- Quotes **cannot** be constructed programmatically; they are recognized only in source files.
- Do **not** put raw newlines inside single-line quotes; use `m5_nl` instead.
- Multi-line literal text: use **text blocks** (see §1.8.5).

**Double quoting — when required:**
```
m5_macro(hello, ['['Hello, $1!']'])
```
The outer `['…']` protects the comma during definition; the inner `['…']` protects the comma after substitution so the result is literal.

**Empty quote as word boundary:**
```
Index['']m5_Index     ← enables m5_Index to expand after "Index"
['Index']m5_Index     ← same effect
```

---

### 1.3 Variables

Variables hold literal string values. They are scoped (Pascal case by convention when scoped).

| Operation | Syntax | Notes |
|-----------|--------|-------|
| Declare | `m5_var(Name, Value)` | Scoped; popped at end of enclosing scope |
| Declare multiple | `m5_var(Name1, Val1, Name2, Val2, …)` | Values required for all |
| Set | `m5_set(Name, Value)` | Updates existing variable |
| Get (sugar) | `m5_Name` | Syntactic sugar for `m5_get(Name)` |
| Get (explicit) | `m5_get(Name)` | Returns literal value; no `$` substitution |
| Declare null | `m5_null_vars(Name1, Name2, …)` | Declares with empty values |
| Push (explicit) | `m5_push_var(Name, Value)` | Must be explicitly popped |
| Pop | `m5_pop(Name)` | Pops `push_var` or `push_macro` |
| Append | `m5_append_var(Name, String)` | Appends string to variable |
| Prepend | `m5_prepend_var(Name, String)` | Prepends string to variable |

**Variable sugar:**
- `m5_Foo` (no trailing `(`) → syntactic sugar for `m5_get(Foo)`
- Do NOT use `m5_Foo` in literal text that will never be evaluated — it will be undesirably sugared.

---

### 1.4 Macros

#### Declaring Macros

```
m5_macro(name, body)
```
- `body` is a string; `$1`, `$2`, … are substituted with arguments on call.
- Result is **evaluated** after substitution.
- To return literal text, wrap body in quotes: `m5_macro(foo, ['literal text'])`

**Special dollar parameters in macro bodies:**

| Parameter | Meaning |
|-----------|---------|
| `$1`, `$2`, … | Positional arguments |
| `$#` | Number of arguments |
| `$@` | Comma-delimited quoted list of all arguments |
| `$*` | Like `$@` but arguments are unquoted (rarely useful) |
| `$0` | Name of the macro itself |
| `$0__` | Unique prefix local to this macro (discouraged; use functions instead) |

**WARNING:** `$@`, `$*`, `$#` in nested macro bodies substitute with the **outer** macro's arguments. Use functions with named parameters for nested declarations.

#### Calling Macros

```
m5_foo(arg1, arg2)
```
- `m5_foo(` is syntactic sugar for `m5_call(foo,`
- A macro call is recognized when: in unquoted text, `m5_` is followed by a defined name followed by `(`
- After substitution, an implicit `['']` word boundary is added.
- Call with zero arguments: `m5_call(macro_name)` (not `m5_foo()` which passes one empty arg)

#### Macro Argument Rules

- Arguments are comma-separated inside `( … )`
- Leading whitespace before each argument is **stripped**; trailing whitespace is **kept**
- Preceding whitespace rule: first non-whitespace char after `(` or `,` starts the argument
- `()` = one empty argument; `(,)` = two empty arguments
- Prefer `([''])` and `([''],[''])` for clarity
- Newlines **before** arguments are stripped; newlines **after** arguments are part of the argument — so break lines before the argument, not after:
  ```
  m5_foo(long-arg1,
  long-arg2)    ← correct; newline before arg2 is stripped
  ```
  Do NOT put the closing `)` on its own line — that includes the newline in the last argument.

---

### 1.5 Functions (`m5_fn`)

Functions are the preferred way to declare non-trivial macros.

```
m5_fn(name, [param-list,] body)
m5_lazy_fn(name, [param-list,] body)
```
- `fn` and `lazy_fn` are functionally equivalent; `lazy_fn` is preferred in libraries (lazy evaluation) but does NOT support `^` (inherited) parameters.
- Function body is a Scoped Code Block `{…}` by convention.

**Basic example:**
```
fn(mul, val1, val2, {
   ~calc(m5_val1 * m5_val2)
})
m5_mul(3, 5)   ⟹  15
```

**One-line body:**
```
m5_fn(mul, val1, val2, ['m5_calc(m5_val1 * m5_val2)'])
```

#### 1.5.1 Parameter List Syntax

Each `<param-spec>` follows the form: `[?][[<number>]][[^]<n>][: <comment>]`

| Modifier | Meaning |
|----------|---------|
| `<n>` | Named parameter — available as `m5_Name` inside body |
| `?` | Optional parameter. Non-optional cannot follow optional. |
| `[<number>]` | Numbered parameter; must be `[1]`, `[2]`, … in order. Can also be named. |
| `^` | Inherited: value comes from the **calling scope's** variable of this name. No corresponding argument in calls. |
| `?^<n>` | Optional inherited parameter |
| `…` | After last numbered param; allows extra arguments. Without this, extra args = error. |
| `: comment` | Documents the parameter |

**Example:**
```
fn(foo, Param1, ?[1]Param2: an optional parameter,
   ?^Inherit1, [2]^Inherit2, ..., {
   ~nl(Param1: m5_Param1)
   ~nl(Param2: m5_Param2)
   ~nl(Inherit1: m5_Inherit1)
   ~nl(Inherit2: m5_Inherit2)
   ~nl(['numbered args: $@'])
})
```

#### 1.5.2 Accessing Function Arguments

| Access Method | Description |
|---------------|-------------|
| `m5_ParamName` | Access named parameter as variable |
| `$1`, `$2`, … | Numbered parameters (substituted throughout body) |
| `m5_fn_arg(N)` | Access numbered argument by position — safe in nested functions |
| `m5_fn_args()` | All numbered args as quoted comma-delimited list (like `$@` but nested-safe) |
| `m5_comma_fn_args()` | Same but with leading comma if non-empty |
| `m5_fn_arg_cnt()` | Count of numbered args (like `$#` but nested-safe) |

#### 1.5.3 Aftermath — Side Effects on Return

Functions restore `m5_status` after body evaluation. To produce side effects in the **calling** scope, use aftermath:

```
m5_on_return(MacroName, arg1, arg2, …)
m5_return_status(Value)    ← shorthand for m5_on_return(set, status, m5_Value)
```

**Use cases for aftermath:**
- Passing arguments by reference
- Returning status
- Evaluating body arguments in the caller's scope
- Tail recursion

**Pass by reference example:**
```
fn(update, FooRef, {
   var(Value, ['updated value'])
   on_return(set, m5_FooRef, m5_Value)
})
set(Foo, ['xxx'])
update(Foo)
~Foo     ⟹  updated value
```

#### 1.5.4 Body Arguments in Functions

When a function takes a body to evaluate, evaluate it via aftermath (not inside the function body) so side effects apply to the caller:

```
fn(if_neg, Value, Body, {
   var(Neg, m5_calc(Value < 0))
   ~if(Neg, [
      on_return(Body)          ← evaluates Body in caller's scope
   ])
   return_status(if(Neg, [''], else))
})
```

#### 1.5.5 Tail Recursion

To avoid stack growth, use aftermath for the recursive call:
```
fn(my_fn, First, ..., {
   ...
   ~unless(m5_Done, [
      ...
      on_return(my_fn\m5_comma_args())
   ])
})
```

---

### 1.6 Syntactic Sugar

#### 1.6.1 Comments

| Syntax | Behavior |
|--------|---------|
| `/// comment text` | Line comment — stripped entirely (including preceding whitespace) |
| `/** comment **/` | Block comment — stripped; newlines preserved |

- Comments are stripped **before** indentation checking and quote/parenthesis matching.
- To include `///` or `/**` in output: `['//']['/']`
- Target-language comments (e.g. `//` in Verilog) are **not** M5 comments. To disable M5 code, use M5 comments.

#### 1.6.2 Macro Call Sugar

`m5_foo(` → syntactic sugar for `m5_call(foo,`
- Verifies the macro exists at sugar-processing time.
- Do not use `m5_foo(` in literal text that will never be evaluated.

#### 1.6.3 Variable Sugar

`m5_Foo` (without trailing `(`) → syntactic sugar for `m5_get(Foo)`

#### 1.6.4 Backslash Word Boundary

| Syntax | Meaning |
|--------|---------|
| `m5_\foo` | Produces `m5_foo` without interpreting as syntactic sugar |
| `\m5_foo` | Shorthand for `['']m5_` — creates a word boundary before `m5_foo` |

---

### 1.7 Status Variable

`m5_status` is a universal variable with reserved usage.
- **Empty** = normal; **non-empty** = exceptional condition or body not evaluated.
- Macros either always set it or never set it (documented in specs).
- Functions automatically **restore** `m5_status` to its pre-body value after evaluation. Aftermath runs after this restore, so `m5_return_status` sets it for the caller.
- `m5_else` / `m5_if_so` act on `m5_status`.
- `m5_sticky_status` captures the first non-empty status across multiple calls.

---

### 1.8 Code Blocks

#### 1.8.1 What are Bodies and Blocks?

- **Immediate body**: Evaluated by the macro that receives it (e.g., `m5_if` body).
- **Indirect body**: Evaluated by callers of the declared macro (e.g., function body).
- **Code block**: Multi-line syntactic sugar for a body argument.

#### 1.8.2 Unscoped Code Blocks `[…]`

```
~if(m5_A > m5_B, [
   ~(['Yes, '])
   ~A
   ~([' > '])
   ~B
])
```
- Block begins with `[` immediately followed by a newline.
- Block ends with `]` that begins a line (after optional consistent indentation).
- First non-blank line sets the indentation level.
- All lines at that indentation level start a **statement**.
- Lines with deeper indentation are continuations.

**Statement types inside a code block:**

| Form | Behavior |
|------|---------|
| `foo(…)` | Macro call — `m5_` prefix implied |
| `~foo(…)` | Macro call with output (tilde required for output-producing statements) |
| `~Var` | Variable elaboration with output |
| `~(['text'])` | Inline output literal |
| `/comment text` | Statement comment — stripped |

**The tilde `~` prefix:**
- Required before statements that produce output.
- `~(…)` syntax produces the given text directly.
- `m5_out_eval` is useful for side effects.

#### 1.8.3 Scoped Code Blocks `{…}`

```
fn(check, Cond, {
   if(m5_Cond, [
      warning(Check failed.)
   ])
})
```
- Uses `{` and `}` instead of `[` and `]`.
- Variable declarations inside are **pushed** at entry and **popped** at exit.
- Recommended for all indirect body arguments (function bodies).
- Immediate body arguments (e.g., `m5_if` bodies) are usually unscoped.
- Variables from outer scopes are visible in inner scopes.
- Redeclaring a variable in the same scope is OK — both definitions are popped.
- By convention, scoped variables use Pascal case (`MyVar`).

#### 1.8.4 Evaluate Blocks `*[…]` / `*{…}`

Preceded by `*` — evaluates code to form a non-body argument:
```
error(*{
   ~(['Arguments include negative values: '])
   var(Comma, [''])
   ~for(Value, ['$@'], [
      ~if(m5_Value < 0, [
         ~Comma
         set(Comma, [', '])
         ~Value
      ])
   ])
   ~(['.'])
})
```

#### 1.8.5 Text Blocks

Multi-line literal text, indented with surrounding code:
```
macro(copyright, ['['
Copyright (c) 20xx
All rights reserved.
']'])
```
- Opening `['` must be followed by a newline.
- Closing `']` must begin a new line at consistent indentation.
- The fixed indentation level (first non-blank line) and surrounding newlines are removed.
- M5 comments and quotes are still recognized inside text blocks.
- No code/statement parsing inside text blocks.

#### 1.8.6 Block Labels

Used to escape from nested quote levels or associate numbered params with an inner block.

```
macro(my_macro, ..., <sf>{
})
```

**Quote escape:**
```
']<label>m5_Expr['
```
Evaluates `m5_Expr` at the level of the labeled block.

**Labeled parameter reference:**
```
$<label>1    ← associates $1 with the labeled block, not the enclosing one
```

---

### 1.9 Syntax Checks and Pragmas

- **Indentation checks**: Enabled automatically for code and text blocks.
- **Quote matching**: Balanced `['` / `']` checked after comments stripped.
- **Parenthesis matching**: Within block quotes, balanced after comments stripped.

**Pragma macros** (elaborate to nothing):
```
m5_pragma_where_am_i()
m5_pragma_enable_debug()
m5_pragma_disable_debug()
m5_pragma_enable_paren_checks()
m5_pragma_disable_paren_checks()
m5_pragma_enable_quote_checks()
m5_pragma_disable_quote_checks()
m5_pragma_enable_verbose_checks()
m5_pragma_disable_verbose_checks()
```

---

### 1.10 Macro Library — Complete Reference

#### 1.10.1 Declaring/Setting Variables

```
m5_var(Name, Value, …)         ← declare scoped variable(s)
m5_set(Name, Value)            ← set existing variable
m5_push_var(Name, Value)       ← push; must be explicitly popped
m5_pop(Name)                   ← pop push_var or push_macro
m5_null_vars(Name1, Name2, …)  ← declare with empty values
```

#### 1.10.2 Declaring Macros

```
m5_fn(…)                       ← declare function
m5_lazy_fn(…)                  ← lazy function (preferred in libraries)
m5_macro(Name, Body)           ← declare scoped macro
m5_null_macro(Name, Body)      ← declare macro that must produce no output
m5_set_macro(Name, Body)       ← set existing macro value (rare)
m5_push_macro(Name, Body)      ← push macro; must be popped
```

#### 1.10.3 Accessing Values

```
m5_get(Name)                   ← get variable value (no $ substitution)
m5_must_exist(Name)            ← assert macro exists
m5_var_must_exist(Name)        ← assert variable exists
```

#### 1.10.4 Status

```
m5_status                      ← universal variable; empty = ok
m5_sticky_status               ← captures first non-empty status
m5_sticky_status()             ← sets sticky_status if status non-empty
m5_reset_sticky_status()       ← tests and resets sticky_status; output: 0 or 1
```

**`m5_sticky_status` pattern:**
```
if(m5_A >= m5_Min, [''])
sticky_status()
if(m5_A <= m5_Max, [''])
sticky_status()
if(m5_reset_sticky_status(), ['m5_error(m5_get(A) is out of range.)'])
```

#### 1.10.5 Conditionals

```
m5_if(Cond, TrueBody, …)
m5_unless(Cond, TrueBody, FalseBody)
m5_else_if(Cond, TrueBody, …)
```
- `Cond` evaluated by `m5_calc` (boolean 0/1); non-0 = true for `if`, 0 = true for `unless`.
- Remaining args: either `FalseBody` or recursive `Cond, TrueBody, …` pairs (`if` only).
- Sets `m5_status` — empty iff a block was evaluated.

```
m5_if_eq(String1, String2, TrueBody, …)    ← equal
m5_if_neq(String1, String2, TrueBody, …)   ← not equal
```
- Chains: remaining args are recursive `String1, String2, TrueBody, …` or `FalseBody`.

```
m5_if_null(Var, Body, ElseBody)          ← if variable is empty
m5_if_def(Var, Body, ElseBody)           ← if variable is defined
m5_if_ndef(Var, Body, ElseBody)          ← if variable is NOT defined
m5_if_defined_as(Var, Value, Body, ElseBody)  ← if defined and equals Value
```

```
m5_else(Body)       ← evaluate if m5_status is non-empty
m5_if_so(Body)      ← evaluate if m5_status is empty
```

**`m5_else` usage pattern:**
```
~if(m5_Cnt > 0, [
   decrement(Cnt)
])
else([
   ~(Done)
])
```

```
m5_else_if_def(Name, Body)   ← evaluate if m5_status non-empty AND Name is defined
m5_case(Name, Value, TrueBody, …)  ← compare variable Name against values
```

#### 1.10.6 Loops

```
m5_loop(InitList, DoBody, WhileCond, WhileBody)
```
- `InitList`: parenthesized `(Var, val, Var2, val2)` pairs or `['']`
- Implicit `m5_LoopCnt` starts at 0, increments after both blocks.
- `WhileBody` is optional.

```
m5_repeat(Cnt, Body)
```
- Evaluates Body `Cnt` times. `m5_LoopCnt` increments from 0.

```
m5_for(Var, List, Body)
```
- Iterates over comma-delimited `List`. Last item skipped if empty.
- `m5_LoopCnt` increments from 0.
- Example: `~for(fruit, ['apple, orange, '], [~do_stuff(...)])`

#### 1.10.7 Recursion

```
m5_recurse(max_depth, macro, …)
```
- Calls macro recursively up to `max_depth` levels.
- `m5_recursion_limit` universal variable — fatal error if exceeded.

---

### 1.11 String Operations

#### Special Characters

```
m5_nl()                    ← newline character — use this, not literal newlines in code
m5_open_quote()            ← literal open quote (use with caution — can imbalance)
m5_close_quote()           ← literal close quote (use with caution)
m5_orig_open_quote()       ← produces [' as literal characters
m5_orig_close_quote()      ← produces '] as literal characters
m5_printable_open_quote()  ← single unicode char representing ['
m5_printable_close_quote() ← single unicode char representing ']
m5_UNDEFINED()             ← unique value for "no assignment made"
```

#### Slicing and Dicing

```
m5_append_var(Name, String)      ← append to variable
m5_prepend_var(Name, String)     ← prepend to variable
m5_append_macro(Name, String)    ← append to macro
m5_prepend_macro(Name, String)   ← prepend to macro

m5_substr(String, From, Length)       ← substring; result is literal
m5_substr_eval(String, From, Length)  ← substring; result is evaluated
```
- Index starts at 0. Length is in **bytes** (ASCII/UTF-8 bytes), not characters.
- **WARNING:** Extracting substrings from strings with quotes is dangerous (can imbalance quoting). If quotes would result, an error is reported. Use `m5_dequote` / `m5_requote` pattern.
- **WARNING:** UTF-8 multi-byte characters can be split — resulting bytes have no special M5 meaning.
- `m5_substr` is **slow** relative to `m5_substr_eval`.

```
m5_join(Delimiter, …)        ← join arguments with delimiter
m5_translit(String, InChars, OutChars)       ← character-for-character substitution; result literal
m5_translit_eval(String, InChars, OutChars)  ← same but result evaluated
m5_uppercase(String)         ← convert to uppercase ASCII
m5_lowercase(String)         ← convert to lowercase ASCII
m5_replicate(Cnt, String)    ← repeat string N times
m5_strip_trailing_whitespace_from(Var)  ← strips trailing whitespace in-place
```

#### Formatting

```
m5_format_eval(string, …)
```
- Like C `printf`. Supported specifiers: `c, s, d, o, x, X, u, a, A, e, E, f, F, g, G, %`
- Supported flags: `+, -, ' ', 0, #, '`
- Supported width modifiers: `hh, h, l` (integers); `l` (floats)
- NOT supported: positional args, `n, p, S, C`, `z, t, j, L, ll`

#### Inspecting

```
m5_length(String)                  ← length in bytes (not unicode characters!)
m5_index_of(String, Substring)     ← position of first match, or -1
m5_num_lines(String)               ← number of newlines in string
m5_for_each_line(Text, Body)       ← iterate lines; m5_Line set to each line (no newline)
```

#### Safe String Handling

```
m5_dequote(String)                 ← replace quotes with surrogate quotes (safe for slicing)
m5_requote(String)                 ← restore surrogate quotes back to real quotes
m5_output_with_restored_quotes(String)  ← output with all quote forms restored to ['']
m5_no_quotes(String)               ← assert no quotes in string
```

**Pattern for safe substring with quotes:**
1. `m5_dequote` the string
2. Slice/process
3. `m5_requote` when balanced surrogate quotes are reconstructed

#### Regular Expressions

M5 uses **GNU Emacs regular expression** syntax (similar to POSIX BRE). Does NOT support: lookahead, lazy matches, character codes.

```
m5_regex(String, Regex, Replacement)        ← result is literal
m5_regex_eval(String, Regex, Replacement)   ← result is evaluated
```
- Without `Replacement`: returns index of first match (0-based) or -1.
- With `Replacement`: `\n` references nth subexpression; `\&` = entire match; `\\` = literal `\`.
- No match with Replacement: empty result.

```
m5_var_regex(String, Regex, VarList)
```
- Declares variables for subexpressions. `VarList` = `(Var1, Var2, …)` in parentheses.
- Sets `m5_status` non-empty if no match.

```
m5_if_regex(String, Regex, VarList, Body, …)
m5_else_if_regex(String, Regex, VarList, Body, …)
```
- Chain pattern matching. `else_if_regex` does nothing if `m5_status` is non-empty.

```
m5_for_each_regex(String, Regex, VarList, Body)
```
- Iterates all matches. `VarList` must be non-empty. String must contain at least one subexpression and no `$`. `m5_status` is unassigned.

---

### 1.12 Utilities

#### Fundamental

```
m5_defn(Name)          ← M4 definition of a macro (slightly different from M5 definition)
m5_call(Name, …)       ← indirect macro call (supports zero args and constructed names)
m5_quote(…)            ← comma-separated quoted list of args ($@)
m5_nquote(N, …)        ← args wrapped in N levels of quotes (innermost individual per arg)
m5_eval(Expr)          ← evaluate the argument
m5_comment(…)          ← discard — produce nothing (M5 block comments preferred)
m5_nullify(…)          ← discard evaluation result
```

#### Macro Stacks

```
m5_get_ago(Name, Ago)      ← get value Ago levels back on stack (0 = current, 1 = previous)
m5_depth_of(Name)          ← number of values on the stack
```

#### Argument Processing

```
m5_shift(…)                ← removes first argument; returns rest
m5_comma_shift(…)          ← like shift but with leading comma if args remain
m5_nargs(…)                ← count of arguments given
m5_argn(N, …)              ← Nth argument (1-based); [''] if non-existent
m5_comma_args(…)           ← convert quoted arg list to args with preceding comma
m5_echo_args(…)            ← returns argument list ($@)
```

#### Arithmetic

```
m5_calc(Expr, Radix, Width)
```
- 32-bit signed integers; overflow wraps silently.
- Operators (highest to lowest precedence):
  `()`, unary `+/-/~/!`, `**` (right-assoc), `*/%`, `+-`, `<<>>`, `>/>=/</<=`, `==/!=`, `&`, `^`, `|`, `&&`, `||`
- All binary except `**` are left-associative.
- Radix prefixes in expressions: `0` (octal), `0x` (hex), `0b` (binary), `0r<N>:` (base N)
- Output: value in given Radix, zero-padded to Width (default base 10, no padding)
- Output digits > 9: lowercase letters; no radix prefix on output

```
m5_equate(Name, Expr)           ← set variable to calc result
m5_operate_on(Name, Expr)       ← like +=, *=: prepends current value
m5_increment(Name, Amount)      ← increment by Amount (default 1)
m5_decrement(Name, Amount)      ← decrement by Amount (default 1)
```

#### Boolean

```
m5_is_null(Name)                ← 1 if variable is empty
m5_isnt_null(Name)              ← 1 if variable is non-empty
m5_eq(String1, String2, …)      ← 1 if String1 equals String2 (or any of remaining)
m5_neq(String1, String2, …)     ← 1 if String1 does NOT equal String2 (or all of remaining)
```

#### Within Functions/Code Blocks

```
m5_fn_args()                    ← numbered args of current function (nested-safe)
m5_comma_fn_args()              ← same with preceding comma if non-empty
m5_fn_arg(Num)                  ← Nth numbered argument (parameterized, nested-safe)
m5_fn_arg_cnt()                 ← count of numbered arguments (nested-safe)
m5_out(String)                  ← capture literal output in code block
m5_out_eval(String)             ← capture evaluated output in code block (useful for side effects)
m5_return_status(Value)         ← set return status via aftermath
m5_on_return(…, MacroName, …)   ← call a macro upon function return (aftermath)
```

---

### 1.13 Checking and Debugging

#### Output to STDERR

```
m5_errprint(text)               ← write to STDERR
m5_errprint_nl(text)            ← write to STDERR with newline

m5_warning(message)             ← warning + stack trace to STDERR
m5_error(message)               ← error + stack trace to STDERR
m5_fatal_error(message)         ← fatal error + exit (non-zero)
m5_DEBUG(message)               ← debug message + stack trace

m5_warning_if(condition, message)
m5_error_if(condition, message)
m5_fatal_error_if(condition, message)
m5_DEBUG_if(condition, message)

m5_assert(condition)            ← fatal error if condition is false
m5_fatal_assert(condition)      ← same as assert
```

#### Argument Verification

```
m5_verify_min_args(Name, Min, Actual)
m5_verify_num_args(Name, Exact, Actual)
m5_verify_min_max_args(Name, Min, Max, Actual)
```

#### Debug Controls

```
m5_debug_level(level)           ← get or set debug level; level: min, default, max
m5_recursion_limit              ← universal variable; fatal error if exceeded
m5_abbreviate_args(max_args, max_arg_length, …)  ← abbreviate long arg lists for messages
```

---

### 1.14 M5 Reference Card Summary

**Core Syntax:**

| Syntax | Purpose |
|--------|---------|
| `///`, `/**`, `**/` | M5 comments |
| `['…']` | Quotes |
| `m5_my_fn(arg1, arg2)` | Macro call |
| `$1`, `$2`, `$@`, `$#`, `$*`, `$0` | Numbered/special params |
| `m5_\foo` / `\m5_foo` | Escape / word boundary |

**Block Syntax:**

| Syntax | Purpose |
|--------|---------|
| `[` / `]` (end/begin line) | Unscoped code block |
| `{` / `}` (end/begin line) | Scoped code block |
| `['…']` (end/begin line) | Text block |
| `*[`, `*{`, `*['` | Evaluate block prefix |
| `/comment` | Statement comment in code block |
| `foo(…)`, `~foo(…)` | Statement (with/without output) |
| `~(…)` | Code block output |
| `<label>` | Block label prefix |
| `']<label>m5_Var['` | Quote escape with label |
| `$<label>N` | Labeled numbered parameter |

---

## 2. TL-X / TL-Verilog Language Syntax

TL-X extends HDLs (Verilog, VHDL, SystemC). TL-Verilog = TL-X + SystemVerilog. Current version: **1d**.

### 2.1 File Format

**First line of every TL-X file (required):**
```
\TLV_version 1d: tl-x.org        ← TL-Verilog
\TLVHDL_version 1d: tl-x.org     ← TL-VHDL
\TLC_version 1d: tl-x.org        ← TL-C
```
(With M5: `\m5_TLV_version 1d: tl-x.org`)

The newline sequence on this line defines the newline sequence for the whole file.

### 2.2 Character Classes

| Class | Characters |
|-------|-----------|
| Word | `[a-zA-Z_]` |
| Numeric | `[0-9]` |
| Space | `[ ]` |
| Newline | LF (`\n`, 0x0A), CR (`\r`, 0x0D), or CR+LF |
| Braces | `()[]{}` |
| Symbols | ``~`!@#$%^&*-+=\|:;"'<>,.?/`` |
| Unrecognized | All other UTF-8 |

**Non-TL-X characters** (non-conformant line terminators + unrecognized): only allowed in HDL contexts.

### 2.3 Code Regions

| Region Start | Language | Content |
|-------------|----------|---------|
| `\SV` | TL-Verilog | Native SystemVerilog |
| `\VHDL` | TL-VHDL | Native VHDL |
| `\C` | TL-C | Native C |
| `\SV_plus` | TL-Verilog | SV with TL-X signal references |
| `\VHDL_plus` | TL-VHDL | VHDL with TL-X signals |
| `\C_plus` | TL-C | C with TL-X signals |
| `\TLV` | TL-Verilog | TL-X logic |
| `\TLVHDL` | TL-VHDL | TL-X logic |

- HDL regions end at the next code region start or end-of-file.
- TL-X and `_plus` regions end when indentation returns to top level.
- Spaces and HDL-style comments may follow the region identifier.

### 2.4 Indentation

- **One level of scope = 3 spaces** (or line-type-char + 2 spaces for first level).
- **Tabs are FORBIDDEN** in TL-X regions.
- Indentation conveys scope; no begin/end delimiters needed.

### 2.5 Line Type Character

First character of every line in `\TLV` / `\SV_plus` regions:

| Char | Meaning |
|------|---------|
| ` ` (space) | Normal, safe TL-X line |
| `!` | **Impure** — required when line contains: HDL signal reference (`*sig`), HDL macro instantiation, or pragma/compiler directive |

### 2.6 Identifier Types

**Prefixes with mixed-case names:**
- `\identifier` — region/keyword
- `*identifier` — HDL signal
- `**identifier` — HDL type
- `^identifier` — attribute

**Scope identifiers:**

| Syntax | Scope Type |
|--------|-----------|
| `\|pipeline` | Pipeline scope |
| `/beh_hier` | Behavioral hierarchy scope |
| `?$when` | When scope (lowercase condition signal) |
| `?$When` | When scope (uppercase = state signal condition) |
| `@1`, `@2`, … | Pipestage scope (positive) |
| `@-1` | Pipestage scope (negative) |
| `@++` | Relative pipestage (increment) |
| `@+=1`, `@+=-1` | Relative pipestage |

**Signal identifiers:**

| Syntax | Type |
|--------|------|
| `$my_sig` | Pipesignal (lowercase) |
| `$$dest_sig` | Explicitly assigned pipesignal |
| `$MyState` | State signal (mixed/upper case — retains value between transactions) |
| `*MyHDL_sig` | HDL signal (mixed case; line must be marked `!`) |
| `**HDL_type` | HDL type |

**Other:**

| Syntax | Meaning |
|--------|---------|
| `>>2` | Ahead reference (2 stages ahead) |
| `<<2` | Behind reference (2 stages behind) |
| `<>0` | Natural/zero alignment |
| `$RETAIN` | Use previous cycle's value of assigned signal |

### 2.7 Identifier Naming Conventions

**Delimited identifiers** (4 styles, same tokens):
- `delimited_identifier` — lower-case
- `DelimitedIdentifier` — camel-case (Pascal)
- `DELIMITED_IDENTIFIER` — upper-case
- `dELIMITEDiDENTIFIER` — reverse camel (not used)

First two alphabetic characters determine the delimitation style. All four styles are equivalent in semantics. First token must start with at least 2 alphabetic characters.

**Mixed-case identifiers:** any alphanumeric + `_`; begin with alphabetic. Used for `\`, `*`, `**`, `^` prefixed identifiers. Do NOT transfer to HDL.

**Numeric identifiers:** prefix + decimal digits; optionally preceded by `+`/`-`.

### 2.8 Ranges and Indices

```
[<expr>:<expr>]    ← Range
[{<expr>:<expr>}]  ← Subset range
[<expr>]           ← Index
[*]                ← Complete range (wildcard)
```
- `<expr>` uses HDL syntax; may contain HDL constants and TL-X signal references.
- `\` is an escape character in ranges: `\:` or `\]` to avoid special parsing.

### 2.9 Scope Summary

| Scope | Range | Nesting | Behavioral | Reentrant |
|-------|-------|---------|------------|-----------|
| Behavioral Hierarchy | none, `[max:min]`, `[{sub:sub}]`, `[*]` | Any | Yes | Yes |
| Pipeline | none | Exactly one required | Yes | Yes |
| Pipestage | none | Exactly one, inside pipeline | No | Yes |
| When | none | Any | No | Yes |
| Source | none | Any | No | N/A |

**Reentrant:** code can define logic in a scope, leave, and re-enter it.

### 2.10 Behavioral Hierarchy

```
/my_hier                         ← namespace only (no replication)
/my_hier[<expr>:<expr>]          ← replicated
/my_hier[{<expr>:<expr>}]        ← replicated, subset of full range
/my_hier[*]                      ← wildcarded replication
```
- A behavioral hierarchy identifier must be distinct from all parent levels.

### 2.11 Pipeline Scope

```
|my_pipe
```
- Cannot be replicated (no range expression).
- Every assignment statement must be within exactly one pipeline.

### 2.12 Pipestage Scope

```
@<number>         ← positive pipestage
@-<number>        ← negative pipestage
```
- Every assignment must be within exactly one pipestage inside a pipeline.

### 2.13 When Scope

```
?$valid_sig          ← conditioned on pipesignal (must be assigned in this scope)
?*HDL_signal         ← conditioned on HDL signal
```
- Condition must be single-bit (boolean); when not asserted, contained signals are "invalid".
- If condition is a pipesignal, its when scope must be the same or a subscope.

### 2.14 Assignment Statements

All assignments begin with `$`, `*`, or `%` (or block keywords with `\` prefix).

**Common form:**
```
$foo = $bar;           ← TL-Verilog; no assign/always_comb/begin/end needed
$foo[7:0] = $bar;
```
- `$` starts the assignment; implicit left-hand side.
- `=` (or `<=` for TL-VHDL) with conformant whitespace on both sides.
- `\` escapes next character: `\$display` → literal $display

**HDL_plus form:**
```
\SV_plus
   <SV code with $pipesignal references>
```
- `$$sig` required for assigned signals here.

**Sequential block (TL-Verilog only):**
```
\always_comb
   expression1;
   expression2;
```
Equivalent to `\TLV_plus` containing `always_comb begin … end`.

### 2.15 Signal Details

- **Pipesignals:** fields of a transaction; invalid when any containing when-scope is false.
- **State signals (`$MyState`):** retain value between invalid transactions; must be assigned with explicit alignment or `<=`.
- **HDL signals (`*sig`):** require `!` on the line; cannot be safely retimed.
- **`$$dest_sig`:** explicit assignment syntax; required in HDL_plus and always_comb blocks.

**One assignment per signal** (generally). Within an assignment block, multiple assignments to same signal are OK if they specify the same type.

**Signal type:**
- Default: single bit (no range)
- With `[N:M]`: vector
- With `**HDL_type`: HDL structure/type

**HDL type declaration:**
```
\SV
   typedef struct { … } struct_name;
\TLV
   |Pipeline
      **struct_name $object_name;           ← type declaration
      @2
         **struct_name $object_name.field1 = …;  ← with assignment
```
**Note:** `$object_name[..]` = bit range; use `$object_name\[..\]` for array indexing.

### 2.16 Pipesignal References

**Simple reference (same scope):**
```
$sig
```

**Cross-scope reference:**
```
/scope|pipe/instr[2]<<2$addr[12:6]
```
- Path: `/scope|pipe/instr[2]` identifies behavioral scope hierarchy.
- `<<2` / `>>3` / `<>0`: pipeline alignment (relative stage offset).
- First path identifier refers to any parent or child scope.
- Top-level scope: implicit identifier `/top`.
- `[*]` wildcard: references concatenation of all instances.
- Assigned signals must have empty path.

**Alignment rules:**
- `<<N`: N stages behind the assignment's stage.
- `>>N`: N stages ahead.
- `<>0`: natural/zero alignment.
- Within a pipeline: natural alignment assumed if none specified.
- Cross-pipeline: explicit alignment required.

**`$RETAIN`:** References the assigned signal delayed by one cycle.

### 2.17 Source Scope

```
\source <file> <line>
```
- Maps generated TL-X lines back to source. Used by preprocessors.
- These lines are not counted in error reporting.
- Multiple levels of `\source` are supported (nested preprocessor macro instantiation).

---

## 3. TL-Verilog Macro Preprocessing Integration

### 3.1 File Structure with M5

```
\m5_TLV_version 1d: tl-x.org
\m5
   use(m5-0.1)                   ← import M5 library
   var(five, 5)                  ← define variables
\SV
   m4_include_url(['https://...']) ← library inclusion
   \TLV my_macro($param1, #const)
   $param1 = #const;
\SV
   m5_makerchip_module
\TLV
   m5+my_macro($foo[7:0], m5_five)
\SV
   endmodule
```

### 3.2 `\m5` Regions

- Begin with `\m5` on its own line.
- Continue until next line with no indentation.
- Define macros for use later; produce no content in resulting TL-Verilog.
- After elaboration, only whitespace/comments should remain.

### 3.3 Within-line Macros

- Defined in `\m5` regions or anywhere.
- Must produce **no carriage returns** (would break line tracking).
- Often variables and simple substitutions.
- Prefix: `m5_`; example: `m5_five` substitutes as `5`.

### 3.4 TLV Macro Block Declarations

```
\TLV <n>(<params>)
<body>
```
- `<n>`: word characters only (`a-zA-Z0-9_`).
- `<params>`: comma-separated parameter names. Names may begin with symbol chars (`~`, `` ` ``, `@`, `#`, `$`, `%`, `^`, `&`, `*`, `+`, `=`, `|`, `\`, `:`, `"`, `'`, `.`, `?`, `/`, `<`, `>`) followed by word chars.
- **Convention:** first word character of a parameter name is `_` (since TL-Verilog identifiers cannot begin with `_`).
- Body is captured as literal string; calls substitute parameter names for arguments then elaborate.
- Matching strings cannot be preceded or postceded by a character that could be part of the name; `['']` creates delimitation.

**Symbol prefix conventions:**

| Prefix | For |
|--------|-----|
| `$` | Pipesignal names and logic expressions |
| `\|` | Pipeline identifiers or paths |
| `@` | Pipestages |
| `/` | Hierarchy identifiers or paths |
| `#` | Elaboration-time constant values |
| (none) | Other, including macro blocks |

### 3.5 TLV Macro Block Calls

```
m5+<n>(<args>)
```
- `<args>`: comma-separated; follows M5 argument list rules.
- May appear anywhere in a `\TLV` region where a TL-Verilog statement could appear.
- Expansion is indented based on calling context.
- Wrapped in `\source` / `\end_source` unless `--fmtNoSource`.

**Multi-line calls (3-space continuation indent):**
```
m5+my_code(arg1,
   arg2, arg3,
   arg4)
```
- Subsequent lines: exactly 3 spaces indent.
- Closing `)` must follow last argument immediately (no newline before it alone).

### 3.6 TLV Block Arguments

Passing TLV code blocks as arguments:
```
m5+simple_if(m5_condition, 1,
   \TLV
   $foo = $bar;
   ,
   \TLV
   $foo = 1'b0;
)
```
- Code blocks and their following `,` or `)`: indented exactly 3 spaces.
- Code blocks are passed literally (implicitly quoted).
- Called within macro body: `m5+_yes_block` (using parameter name with `m5+`).

**Macro definition accepting TLV block params:**
```
\TLV simple_if(_cond, _yes_block, _no_block)
m5_if(_cond, ['m5+_yes_block'], ['m5+_no_block'])
```

### 3.7 Procedural TLV Code Generation

```
m5_TLV_fn(name, [params,] body)
```
- Like `m5_fn` but output is TL-Verilog code.
- Output must begin with a new line.
- Indentation added so output lines with no indentation align with the call.
- Called with `m5+` notation.
- Avoids `\source` / `\end_source` overhead.

### 3.8 Library Inclusion

**Verilog/SystemVerilog by URL:**
```
\SV
   m4_sv_include_url(<URL> [, <n>])
```
- Downloads to `sv_url_inc/<filename>`, outputs a `` `include ``.
- Requires Verilator include path to include `sv_url_inc/`.

**TL-Verilog library by URL:**
```
\SV
   m4_include_lib(<URL>)
```
- Downloads and elaborates inline; definitions persist.
- `\m5` regions and `\TLV` macro blocks are preserved; `\TLV`, `\SV`, `\SV_plus` content is discarded (but elaborated).
- To expose content: `m5_show(<text>)` (use sparingly, mainly for `m4_sv_include_url` chaining).

---

## 4. Visual Debug (VIZ) API

### 4.1 Overview

- Works with any HDL that produces `.vcd` trace files.
- Requires: single global `clk` signal + single global `reset` signal in trace.
- File format: `.tlv` extension, processed by Redwood EDA tools (SandStorm or Makerchip).
- Visualization code: JavaScript inside `\viz_js` blocks.
- Graphics library: Fabric.js (version 4.5.0).

### 4.2 Minimal VIZ File Structure

```
\m5_TLV_version 1d: tl-x.org
\SV
\TLV
   \viz_js
   template: {dot: ["Circle", {radius: 2, fill: "black"}]},
   render() {
      let heat = this.sigVal("sensor1.heat").asInt();
      let dot = this.obj.dot;
      dot.set("fill", `#${heat.toString(16).padStart(2, "0")}0000`);
   }
```

**CRITICAL:** Inside `\viz_js` blocks:
- Only **double quotes** for strings — single quotes have special meaning (TL-Verilog signal references).
- Single-quoted text like `'$my_sig'` is a TL-Verilog pipesignal reference.

### 4.3 `\viz_js` Block Structure

Each `\viz_js` block defines a JavaScript object (contents between `{}`). All properties are optional.

**Indentation:**
- Each level up to `\viz_js`: exactly 3 spaces.
- VIZ code inside: any number of spaces indented below `\viz_js`.
- `\viz_js` blocks end when indentation returns to the `\viz_js` level or above.
- Every logical scope (`/hier`, `|pipeline`) can have at most one `\viz_js` block (but multiple parse scopes for the same logical scope can each have one).

### 4.4 Coordinate System

- `box` defines component coordinate system; upper-left is `(0, 0)`.
- `width` and `height` default to bounding box of children; minimum 1x1.
- For replicated scopes: layout is vertical if `height < width`, horizontal if `height > width`.
- `where` properties: position in parent coordinate system.

### 4.5 Complete `\viz_js` Property Reference

#### Top-Level Shorthand Properties
```javascript
width     // shorthand for box.width
height    // shorthand for box.height
fill      // shorthand for box.fill
stroke    // shorthand for box.stroke
strokeWidth  // shorthand for box.strokeWidth
left      // shorthand for box.left
top       // shorthand for box.top
```

#### `box: { … }`
```javascript
box: {
   left, top, width, height,    // coordinate system bounds; min width/height = 1
   fill,                        // background color; default: transparent
   stroke,                      // border color; default: "#808080" (translucent gray)
   strokeWidth,                 // default: 1 (or 0 if fill given without stroke)
}
```
- `strokeWidth` limited to 1/3 of box height and width.
- Stroke is drawn inside the given bounds (adjusted internally).
- Modifiable in `render()`: `stroke`, `rx`, `ry`, etc. NOT: `left`, `top`, `width`, `height`, `strokeWidth`, `fill`.
- Access in render: `this.obj.box` or `this.getBox()`.

#### `template: { … }`
```javascript
template: {
   dot: ["Circle", {left: 10, top: 10, radius: 2, fill: "black"}],
   frame: ["Rect", {left: 0, top: 0, width: 50, height: 30}],
}
```
- Called once per block (not per instance) — performance optimization.
- Objects created and added to each instance before `init()`.
- Accessible in other functions via `this.obj.<n>`.
- `this` in template = `{}`; properties added are shallow-copied to per-instance `this`.

#### `init()`
```javascript
init() {
   // Called once per instance; no trace data access.
   // Returns a JavaScript object of Fabric.js objects.
   return { myRect: new fabric.Rect({…}) };
}
```

#### `render()`
```javascript
render() {
   // Called for each instance on each cycle change.
   // Returns array of Fabric.js objects (bottom to top).
   let val = this.sigVal("path.signal").asInt();
   this.obj.dot.set("fill", "red");
   return [new fabric.Text(val.toString(), {…})];
}
```
- Objects returned are created and destroyed per cycle automatically.
- Modified `template`/`init` properties persist — must always be set or restored via `unrender()`.

#### `renderFill()`
```javascript
renderFill() {
   // Returns background color string based on simulation state.
   return this.sigVal("path.signal").asBool() ? "blue" : "gray";
}
```

#### `unrender()`
```javascript
unrender() {
   // Called once for every render() call when rendering no longer needed.
}
```

#### `onTraceData()`
```javascript
onTraceData() {
   // Called per instance when new trace data available. Returns optional:
   return {
      minCyc: 0,
      maxCyc: 1000,
      objects: { … }
   };
}
```

#### `sigs()`
```javascript
sigs() {
   // Pre-declare signal references for performance.
   return {
      myAlive: '$alive',
      myOther: this.sigVal("path.other"),
   };
}
```

#### `where: { … }` and `where0: { … }`
```javascript
where: {
   top: 20, left: 30,           // position in parent coordinate system
   angle: 0,                    // clockwise degrees
   scale: 1.0,                  // X and Y scaling factor
   scaleX, scaleY,              // override scale
   width, height,               // bounds (determines max scale)
   justifyX: "left",            // "left"/"center"/"right"
   justifyY: "top",             // "top"/"center"/"bottom"
   name: "instance1",
   visible: false,              // true to show where area as fabric.Rect
}
```
- `where`: embedding of scope+instances in parent.
- `where0`: embedding of instance zero in the `all` component.

#### `layout`
```javascript
layout: "horizontal"   // or "vertical"
layout: {
   left: box.width,    // offset per instance from previous (or function of index)
   top: 0,
   angle: 0,
}
```
- `"horizontal"` = `{left: box.width}`; `"vertical"` = `{top: box.height}`
- Default: vertical if `height < width`; horizontal if `height > width`.

#### `all: { … }`
```javascript
all: {
   // Properties for collection-of-instances level.
   // Same as viz_js body EXCEPT: no all, where, layout.
}
```

#### `lib: { … }`
```javascript
lib: {
   // Library functions shared across viz_js blocks in same TL-Verilog scope.
   // Access from other blocks: '/some[]/scope'.lib
}
```

#### `overlay: { … }`
```javascript
overlay: {
   template: { … }, init() { … }, render() { … }
   // Layered above children; does not impact bounds.
}
```

#### `dynamicSigs()`
```javascript
dynamicSigs() {
   // Never called; static refs here declare dynamic signal dependencies.
   '$potential_sig';
}
```

### 4.6 VIZ Execution Context (`VizJSContext`)

`this` in all `\viz_js` functions:

```javascript
this.getCycle()                        // active cycle number
this.getIndex()                        // index of this instance in scope
this.getIndex("scope_name")            // index of named ancestor scope
this.steppedBy()                       // cycle delta from previous render (0 = first)
this.obj                               // objects from template/init/render + this.obj.box
this.getObjects()                      // same as this.obj
this.getScope()                        // Object for definition scope (TBD)
this.getScope("name")                  // Object for named ancestor (null if not found)
this.sigVal(sig_name, cyc_offset = 0)  // access signal value
this.ms(ms)                            // time adjusted for playback speed
```

**Sandboxed `window`:** standard subset + `wait(ms)` (async delay).

### 4.7 Signal Value Access

#### `this.sigVal(sig_name, cyc_offset = 0)`
- `sig_name`: full dot-separated path as in `.vcd` file.
- `cyc_offset`: offset from current cycle; should be multiple of 0.5.
- Returns `SignalValue`. If not found: currently `undefined`.

#### Pipesignal reference (TL-Verilog, single quotes)
```javascript
'$alive'
'>>1$addr[12:6]'
'/scope|pipe/inst[2]<<2$sig'
```
- Only valid inside `render()` and `renderFill()`.
- Returns `SignalValue`.
- **WARNING with M5:** `['$foo'.asInt()]` misinterpreted. Use `[ '$foo'.asInt() ]` (space before `'`).

#### `SignalValue` Methods
```javascript
sv.asBool(default = undefined)   // boolean; null if dont-care/invalid/incompatible
sv.asInt(default = undefined)    // integer
sv.asString(default = undefined) // string
sv.asReal(default = undefined)   // float
sv.step(cycle_delta = 1)         // adjust referenced cycle; returns modified ref
```
- `null` if signal is dont-care, invalid (when condition false), or wrong type.

### 4.8 Animation

```javascript
// Immediate set
this.obj.dot.set("fill", "red");
this.obj.frame.set({stroke: "blue", fill: "green"});

// Animated set
this.obj.arrow.animate("angle", 90, {duration: 200});
this.obj.marker.animate({left: 100, width: 20}, {duration: 200});

// Chained animation
this.obj.marker
   .animate({left: 100}, {duration: 200})
   .thenAnimate({left: 0}, {duration: 200})
   .thenWait(100)
   .thenSet({angle: 0});
```

**Rules:**
- `animate`, `thenAnimate`, `wait`, `thenWait` return the Object.
- Use `this.ms(ms)` for time values — adjusted for playback speed.
- Use `unrender()` for cleanup, NOT `onComplete`/`abort` (asynchronous).
- VIZ auto-handles: canvas rendering, stopping animation on cycle change, playback speed.

**Animation consistency:** `render()` must be deterministic per cycle regardless of previous state. Three approaches:
1. Return objects from `render()` — auto-created/destroyed per cycle.
2. Restore modified properties in `unrender()`.
3. Always assign properties in `render()` before animating.
4. Use `steppedBy()` to animate forward vs. backward.

### 4.9 Hierarchy in VIZ

```
\TLV
   /yy[3:0]
      \viz_js
      where: {layout: "vertical"}
      /xx[3:0]
         $alive = ...;
         \viz_js
         where: {layout: "horizontal"},
         renderFill() {
            return '$alive'.asBool() ? "blue" : "gray";
         }
```
- Each `\viz_js` for a replicated hierarchy creates 2 levels: scope + instance.
- Every logical scope can have at most one `\viz_js`.

### 4.10 Modular/Reusable VIZ Components

```
\TLV my_component(/_name, _where, _base_name)
   /_name
      \viz_js
      where: { _where },
      render() {
         ...this.sigVal(_base_name + "sig_name")...
      }
```

Instantiation:
```
\TLV
   m5+my_component(/foo, ['top: 20, left: 20'], `top.`)
   /child[1:0]
      m5+my_component(/bar, ,
         `top.child[${this.getIndex()}].`)
```

### 4.11 Processing Order

1. Evaluate properties (leaf-first), including `all`.
2. Per instance: recurse children → `template` → `init()` → `overlay.template` → `overlay.init()`.
3. On new trace data: `onTraceDataTopDown()` top-down → recurse → `onTraceData()` leaf-first.
4. On cycle change: recurse visible children → `renderFill()` and `render()`.

### 4.12 Debugging VIZ

- Open browser DevTools (`Ctrl+Shift+I`).
- Parse errors: reported in Console.
- Runtime errors: reported in Console; execution pauses on `debugger` statement.
- Canvas objects not in HTML DOM.
- Use explicit `debugger;` statements in `\viz_js` functions.

---

## 5. Critical Gotchas & Common Mistakes

### M5 Gotchas

1. **Nested macro numbered params:** `$1` in nested body = OUTER macro's arg. Use named params (`m5_fn`) for nested declarations.

2. **Trailing whitespace in args:** `m5_foo( A , B )` → `{A ;B }` not `{A;B}`. Trailing whitespace IS kept; leading IS stripped.

3. **Closing paren on new line:** Puts newline+spaces into the last argument. Put `)` immediately after last arg on the same line.

4. **`m5_Foo` in literal text:** Gets sugared even in never-evaluated text. Use `m5_\Foo` or quotes.

5. **`m5_foo(` in literal text:** Gets sugared. Use quotes or `m5_\foo(`.

6. **`m5_substr` with unicode:** Operates on bytes, not characters. Can split multi-byte UTF-8 chars.

7. **`m5_substr` with quotes:** Can create imbalanced quoting → error. Use `dequote`/`requote` pattern.

8. **`m5_length` returns bytes:** Not Unicode character count.

9. **`m5_status` in function bodies:** Functions automatically restore it. Use `m5_return_status` to set it for callers.

10. **`m5_out` in function blocks:** Not recommended. Functions have aftermath for side effects.

11. **Body args inside function:** Side effects apply to the function, not the caller. Use `m5_on_return(Body)`.

12. **`m4_` prefix:** Do not use directly. Do not elaborate `m4_` in strings.

13. **Target-language comments:** `//` in Verilog is NOT an M5 comment. Use `///` to disable M5 code.

14. **`m5_lazy_fn` limitations:** Does not support `^` (inherited) parameters.

15. **M5 regex syntax:** GNU Emacs (BRE-like). No lookahead, lazy matches, character codes. Use `\(…\)` for subexpressions.

16. **`m5_patsubst`:** Cannot return quoted text. Use `m5_for_each_regex` instead.

### TL-Verilog Gotchas

1. **Tabs in TL-X regions:** Forbidden. Use spaces only (3 per indent level).

2. **HDL signal reference (`*sig`):** Line MUST be marked `!` (impure). Cannot be safely retimed.

3. **Signal type:** Default is single bit. Specify `[N:M]` for vectors.

4. **One assignment per signal:** Generally required. Exception: within an assignment block, multiple OK if same type.

5. **State signals (`$MyState`):** Must be assigned with explicit alignment or `<=`. Retains values on invalid transactions.

6. **`$$sig` required:** In HDL_plus and always_comb blocks, assigned signals must use `$$sig` prefix.

7. **`\always_comb`:** TL-Verilog only. Shorthand for `\TLV_plus` with `always_comb begin…end`.

8. **`\SV` region required:** Even in VIZ-only files (currently required for Verilog translation).

9. **Scope reentrance:** A scope can be entered, exited, and re-entered by design.

10. **Pipeline scopes cannot be replicated:** No range expression on `|my_pipe`.

### VIZ Gotchas

1. **Single quotes in `\viz_js`:** TL-Verilog signal reference syntax. Always use double quotes for strings.

2. **M5 and single quotes:** `['$foo'.asInt()]` → M5 interprets `['` as open quote. Use `[ '$foo'.asInt() ]`.

3. **`render()` must be deterministic per cycle:** Regardless of which cycle was previously rendered.

4. **No `onComplete`/`abort` for cleanup:** Use `unrender()` — async completion can race with cycle changes.

5. **`sigVal` returns `undefined` if not found:** Currently. Future: non-existent SignalValue.

6. **`this.sigVal` / `'$sig'` only in render functions:** Not valid outside `render()` and `renderFill()`.

7. **Fabric.js stroke:** Drawn centered on Rect border; VIZ adjusts so stroke stays within given `width`/`height`.

8. **Same Fabric Object in multiple places:** Causes malformed canvas hierarchy and rendering issues.

9. **`box.left/top/width/height/fill/strokeWidth`:** Must NOT be modified in `render()`.

10. **Layout default ambiguity:** If `height == width`, direction is unpredictable. Always specify `layout` explicitly.

11. **`this.ms(ms)` for timers:** Use when calling `setTimeout` etc. to adjust for playback speed.

12. **Fabric.js version:** 4.5.0.

---

## Quick Reference

### M5 Core Operations Cheatsheet

```
DECLARE:   var(Name, Value)              SET: set(Name, Value)
ACCESS:    m5_Name  OR  get(Name)
MACRO:     macro(name, ['body'])         FUNCTION: fn(name, Param1, Param2, { body })
IF:        ~if(cond, [true], [false])    LOOP: ~for(Var, ['a, b, c, '], [body])
CALC:      calc(a + b * c)              STRING LEN: length(str)
SUBSTR:    substr(str, from, len)        JOIN: join([', '], a, b, c)
ERROR:     error(['msg'])               DEBUG: DEBUG(['msg'])
COMMENT:   /// line   OR   /** block **/
OUTPUT:    ~(text)   OR   ~Var   OR   ~macro_call(…)
QUOTE:     ['literal text with, commas']
NO-EVAL:   m5_\foo  (suppress sugar on m5_foo)
WORD-BOUND: \m5_foo  (force word boundary before m5_foo)
```

### TL-Verilog Structure Template

```
\m5_TLV_version 1d: tl-x.org
\m5
   use(m5-0.1)
   var(MyConst, 8)
\SV
module top(input clk, input reset, …);
\TLV
   |my_pipe
      /my_hier[3:0]
         @1
            $valid = …;
         ?$valid
            @2
!              $data[7:0] = *input_port;
               $result = $data + m5_MyConst;
\SV
endmodule
```

### VIZ Block Template

```
\TLV
   /scope[N:0]
      \viz_js
      where: {layout: "vertical"},
      box: {width: 40, height: 20, fill: "white"},
      template: {dot: ["Circle", {radius: 5, fill: "black"}]},
      renderFill() {
         return '$valid'.asBool() ? "blue" : "gray";
      },
      render() {
         let val = this.sigVal("top.signal_name").asInt(0);
         this.obj.dot.set("fill", val > 0 ? "red" : "black");
      }
```

---

*Sources: M5 Text Processing Language User's Guide (v1.0, 2023); TL-Verilog Macro-Preprocessor User Guide (Draft, 2022); TL-X 1d HDL Extension Syntax Specification; Visual Debug User Guide (Draft, 2022). All by Redwood EDA, LLC.*
