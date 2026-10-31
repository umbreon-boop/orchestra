# Contributing to this repository

Bug reports, tests, code, and feedback are all welcome. Report bugs and request features through the issue tracker, and send code through pull requests.

---

## Table of Contents

- [Getting Started](#getting-started)
- [Code Style and Formatting](#code-style-and-formatting)
- [Commit Messages](#commit-messages)
- [Submitting Changes](#submitting-changes)
- [License](#license)
- [Code of Conduct](#code-of-conduct)

---

## Getting Started

The only hard dependency is `mise`, which manages the toolchain on a per-repository basis. Install it:

```bash
curl -fsSL https://mise.run | sh
```

Then clone the repository and install the required tools:

```bash
git clone https://github.com/umbreon-boop/orchestra
cd orchestra
mise install
```

Run `mise tasks` to list every available task. The ones used in this guide are `mise lint` and `mise doc`.

---

## Code Style and Formatting

This project is written in Luau. `mise lint` applies basic formatting automatically and reports everything it cannot fix. When this guide and the linter disagree, the linter wins and this guide should be corrected.

### General Formatting

- Indent with tabs.
- Use double quotes, except when the string itself contains a double quote.
- No trailing commas.
- Maximum line width is 120 characters.
- Files must end with a newline.

### Naming Conventions

No underscores or dashes in names, unless a later rule explicitly allows them.

- Game services, classes, and methods use PascalCase.
- Private members (methods and properties) are prefixed with `_`, e.g. `_ensure`, `_use`, `_cache`. This is the only place a leading underscore is allowed.
- Multi-use literals use SCREAMING_SNAKE_CASE. Underscores are allowed here, e.g. `MAX_RETRIES`.
- All other variables use camelCase.
- Abbreviations are not allowed at module scope, even for names that are not visible to other modules.
- Prefer names of one or two words. A name may be longer when the alternative is an abbreviation or an unclear name, which is common with multi-word literals.

### File Structure and Definitions

- Module imports, service references, constants, and variable initializations go at the top of the file, preferably in that order.
- Prefer logical operator assignments (`and`/`or`) over `if` statements or Luau `if` expressions when both branches assign the same variable. Do not build long chains or nest them more than two levels deep.
- The entire public API requires type annotations on parameters and return types. Private and internal members do not need them.
- Defining a custom exported type for a public function's return value is optional, as long as the `@return` tag in its doc comment documents the shape correctly.

### Documentation

`mise doc` generates documentation from LuaDoc-style source comments. Omit the blank line before a tag when the doc block has only that one tag.

```lua
--[=[
	A very cool example with an even cooler explanation.
	@class Exampler
]=]
local Input = game:GetService("UserInputService")
-- in practice each category would be large enough to be worth separating
local Exampler = {}
local MAX_RETRIES = 3
local lastInput = Input and {} or nil

--[=[
	The shape returned by Exampler.New.

	@interface Example
	@field some boolean Does black box magic
]=]
export type Example = {
	some: boolean
}

--[=[
	Creates a new instance of Example.
	@return Example
]=]
function Exampler.New(): Example
	return {some = false}
end

function Exampler._ensure()
	-- private members are exempt from type annotations
end

return Exampler
```

---

## Commit Messages

We follow conventional commit style:

| Type | Description | Example |
|---|---|---|
| `feat` | New feature | `feat: added position estimations using quantum entanglement` |
| `fix` | Bug fix | `fix: correct approximations of protein folding` |
| `docs` | Documentation update | `docs: add usage section to README` |
| `refactor` | Code change that improves structure | `refactor: optimize metatable logic` |

Reference related issues in the footer, e.g. `Fixes #42`.

---

## Submitting Changes

- Keep changes focused and small.
- Run `mise lint` and resolve everything it flags before submitting.
- Test every modified script for bugs and regressions, or ask someone else to test it. Describe what was tested in the pull request.
- Changes are reviewed and merged through the platform's pull request system.

---

## License

By submitting a contribution, you agree that it is licensed under the same license as the repository.

---

## Code of Conduct

By contributing, you agree to uphold the following:

- Be respectful and considerate.
- Welcome newcomers and different perspectives.
- Assume positive intent.
- Give constructive technical feedback, not personal criticism.

---
Thank You!

Every contribution, no matter the size, helps this project grow. We appreciate your effort, your ideas, and your collaboration.
