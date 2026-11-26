# Code standards

These rules govern changes to this repo. They come from the shared rules in `goui`, `reader-hero`,
`thor` and `onlymuse`. `ulem` and `safetyper` were read too, but their type and framework rules do
not apply to Lua scripts or shell installers. When a rule makes the code worse, keep the better code
and give the reason in the commit message. Never drop a rule silently.

## 1. Write for the reader

Judge code by how long another person needs to understand it. A short line that needs a second read
is worse than a longer line that does not. A reader holds about four things in mind at once. Keep
each block within that. This rule settles every tie below.

## 2. Plain words and full names

- Write full words. `errorCount`, never `nErr` or `err`. A long name is fine.
- A boolean reads as a question: `isCapturing`, `hasPreset`.
- A function is a verb and its subject: `restoreLights`, `findMasterPlayer`.
- One verb has one meaning. Use `read`, `find`, `list`, `build`, `apply`, `set`, `is`, `has`.
- One thing has one name everywhere. A name the game or a library owns keeps its spelling.
- A number carries its unit in its name: `timeoutSeconds`, `distanceSquared`.
- No em dashes or en dashes in prose. Read each sentence aloud.

## 3. A comment is rare

The default is no comment. Write one only when deleting it would leave a reader stuck. It gives a
reason the code cannot, such as a game or engine behaviour, a formula source, or a unit a name cannot
hold. One line. No banners, step narration, or history. A limit the person chose to keep starts with
`shortcut:`, then names the limit and when to remove it.

## 4. Structure

- A function runs in three parts: set up the values, check them with early exits, then do the main
  work. The main path comes last.
- One statement per line. Never pack two statements after a `then`, a `do` or an `end`.
- A blank line groups a block of about five statements. Declare, then use. A run of declarations
  has a blank line around it.
- Multi-line control flow has a blank line above and below it, unless it opens or closes its block.
- A return block is led by a blank line. Every `return` on its own line has a blank line above it.
  A one-line early exit such as `if not camera then return end` stays in its run, which has a blank
  line above it. A function of three lines or fewer may return on its first line.
- Keep `if` blocks shallow. A nested `if` is an antipattern. Return early, name the compound
  condition, use `elseif`, or split the function. A condition inside a loop is not nesting when the
  loop does nothing else.
- Name a compound condition before you test it: `local canCull = isVisible and isFar`.
- Name a lookup table above the line that indexes it. A ternary fits on one line and is never nested.

## 5. Functions and parameters

- A function does one job. Keep it under 15 branch points. Count `if`, `elseif`, `for`, `while`,
  `else`, `and`, `or` and a ternary.
- Extract at two call sites when the copies could disagree. Do not move branches into a helper only
  to lower the count. Before a new helper, ask whether putting its code back would be harder to
  follow.
- A parameter changes a detail of the same job. It never swaps the job; split the function instead.
- A filter that means "everything" is a named value such as `"all"`, never `nil`. Give no default to
  a value a caller must choose.
- Check a value once, where it enters: a settings file, an engine hook, a game object. Code past
  that point trusts it.

## 6. Scope of a change

Touch only what the task needs. Match the style already in the file. Do not tidy nearby code. Fewer
lines wins a tie, but a name that saves the reader time stays even when it costs a line.
