# AI Coding Agent

Project-specific instructions for AI agents working on the Discourse codebase. MUST be loaded at conversation start.

## Default
- Expert Discourse architect mode by default: detailed analysis, patterns, trade-offs, architectural guidance
- Do not assume context, always ask for more when ambiguous
- DO not brute force the solution, question your own solution and check for more fundamental approaches

## Development Rules
- Codebase has established patterns, do not introduce new ones without discussion
- Do not write comments when it is obvious what the code is doing
- If comments need to be written, do it in lowercase and super concise

### Rspec
- Do not add `require "rails_helper"`
- Do not do `Rspec.describe` but just `describe`
- Favour using fab over creating via models if the fabricators exist.
    - use `fab!(:post)` instead of `fab!(:post) { Fabricate(:post) }`
    - use `fab!` over `let!`
    - prefer to fab objects within the `it` blocks if it's only used there
- Prefer have_received for setting message expectations. Setup as a spy using allow or instance_spy.
- Use expect_enqueued_with(job: :job_name, args: {}) for job expectations

### Rails
- When constructing queries, never use `pluck` as it loads results into memory. Use `select` where it's appropriate.
- Be very very mindful of N+1s

### Migrations
- Migrations should not use ActiveRecord models, use raw SQL or DB helpers as per Discourse norms
- Models may have thousands or millions of records
- Avoid into memory, process them in batches processing majority / all records or if unknown

### EmberJS
- Never use triple curly braces `{{{ }}}` in templates.
- Be careful of html safety, avoid using `.htmlSafe()` unless absolutely necessary.

## Changes made
- When changes need to be made, write tests
  - If gjs change, write qunit tests, and consider rspec system specs if UI is affected
  - If ruby change, write rspec tests
- Go through these points when implementing features
  - test that working on deleted topics or posts (or categories) do not cause errors
  - anonymous users or non-logged in users
  - when working with categories, test subcategories
  - when working with topics, test topic archetypes - private (PM) and topics in private categories
  - when working with strings or URLs, test unicode support with 字
  - accessibility - ensure that aria titles are presented
  - UI
      - rtl text
      - dark-mode
      - mobile `?mobile_view=1`
  - controller, ensure frontend validations and no API bypass
  - plurality in i18n, make sure count `one:, many:,`
  - cache, anon cache, cache poisoning, cache key is sufficiently covered
  - sites hosted using subfolders in URLs
  - multisite safety
