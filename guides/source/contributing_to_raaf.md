**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf.ai>.**

Contributing to Ruby AI Agents Factory
======================================

This guide covers how _you_ can become a part of the ongoing development of Ruby AI Agents Factory (RAAF).

After reading this guide, you will know:

* How to use GitHub to report issues.
* How to clone main and run the test suite for the mono-repo.
* How to help resolve existing issues.
* How to contribute to the RAAF documentation.
* How to contribute to the RAAF code across multiple gems.

Ruby AI Agents Factory is not "someone else's framework". RAAF is a comprehensive Ruby implementation of AI Agents with enterprise-grade capabilities for building sophisticated multi-agent workflows. Even if you don't feel up to writing code or documentation yet, there are various other ways that you can contribute, from reporting issues to testing patches across the 14+ gems in our mono-repo.

### Our Development Journey with Claude Code

We want to be transparent about how RAAF was developed. This project was built extensively using Claude Code, [Anthropic](https://www.anthropic.com)'s AI-powered development assistant. This collaboration with AI had both tremendous benefits and some challenges:

**How Claude Code Helped:**

- **Rapid prototyping**: Claude Code enabled us to quickly implement complex AI agent patterns and multi-provider integrations
- **Documentation generation**: Much of our comprehensive documentation was generated with Claude Code's assistance
- **Meta-level architecture**: Claude Code excelled at understanding high-level requirements and translating them into working Ruby code
- **Code consistency**: It helped maintain consistent patterns across our 14+ gem mono-repo structure

**Challenges We Encountered:**

- **Occasional hallucinations**: Sometimes Claude Code would generate code referencing non-existent methods or incorrect API signatures
- **Context limitations**: In complex scenarios, Claude Code would sometimes lose track of the broader system architecture
- **Over-engineering**: There were instances where Claude Code would create overly complex solutions for simple problems

**Our Approach:**
We tried to guide Claude Code as effectively as possible by providing clear requirements, architectural constraints, and iterative feedback. However, we acknowledge that you may encounter code or documentation that doesn't make complete sense, contains inconsistencies, or seems unnecessarily complex.

**If You Find Issues:**
We apologize in advance for any code or documentation that may be confusing or incorrect. If you encounter anything that seems off, please don't hesitate to:

- [Open an issue](https://github.com/raaf-ai/raaf/issues) describing what you found
- Submit a pull request with improvements
- Ask questions in [GitHub Discussions](https://github.com/raaf-ai/raaf/discussions)

This transparency about our development process is important because it helps set expectations and encourages community involvement in improving the codebase. RAAF is fundamentally a collaborative effort between human developers and AI assistance, and your contributions help make it better for everyone.

As mentioned in [RAAF's
README](https://github.com/raaf-ai/raaf/blob/main/README.md), everyone interacting in RAAF and its sub-projects' codebases, issue trackers, chat rooms, discussion boards, and mailing lists is expected to follow the RAAF [code of conduct](https://github.com/raaf-ai/raaf/blob/main/CODE_OF_CONDUCT.md).

Before contributing, please review our comprehensive [Contributing Guidelines](https://github.com/raaf-ai/raaf/blob/main/CONTRIBUTING.md) which includes important information about intellectual property licensing, contributor requirements, and the Developer Certificate of Origin (DCO).

--------------------------------------------------------------------------------

Reporting an Issue
------------------

Ruby AI Agents Factory uses [GitHub Issue Tracking](https://github.com/raaf-ai/raaf/issues) to track issues (primarily bugs and contributions of new code). If you've found a bug in RAAF, this is the place to start. You'll need to create a (free) GitHub account to submit an issue, comment on issues, or create pull requests.

NOTE: Bugs in the most recent released version of RAAF will likely get the most attention. Additionally, the RAAF core team is always interested in feedback from those who can take the time to test _edge RAAF_ (the code for the version of RAAF that is currently under development). Later in this guide, you'll find out how to get edge RAAF for testing. See our [maintenance policy](maintenance_policy.html) for information on which versions are supported. Never report a security issue on the GitHub issues tracker.

### Creating a Bug Report

If you've found a problem in RAAF that is not a security risk, search the [Issues](https://github.com/raaf-ai/raaf/issues) on GitHub, in case it has already been reported. If you cannot find any open GitHub issues addressing the problem you found, your next step will be to [open a new issue](https://github.com/raaf-ai/raaf/issues/new). (See the next section for reporting security issues.)

We've provided an issue template for you so that when creating an issue you include all the information needed to determine whether there is a bug in the framework. Each issue needs to include a title and clear description of the problem. Make sure to include as much relevant information as possible, including a code sample or failing test that demonstrates the expected behavior, as well as your system configuration. Your goal should be to make it easy for yourself - and others - to reproduce the bug and figure out a fix.

Once you open an issue, it may or may not see activity right away unless it is a "Code Red, Mission Critical, the World is Coming to an End" kind of bug. That doesn't mean we don't care about your bug, just that there are a lot of issues and pull requests to get through. Other people with the same problem can find your issue, and confirm the bug, and may collaborate with you on fixing it. If you know how to fix the bug, go ahead and open a pull request.

### Create an Executable Test Case

Having a way to reproduce your issue will help people confirm, investigate, and ultimately fix your issue. You can do this by providing an executable test case. To make this process easier, we have prepared several bug report templates for you to use as a starting point:

* [Template for RAAF Core (agents, runners) issues](https://github.com/raaf-ai/raaf/blob/main/guides/bug_report_templates/core.rb)
* [Template for RAAF Tools issues](https://github.com/raaf-ai/raaf/blob/main/guides/bug_report_templates/tools.rb)
* [Template for RAAF Providers issues](https://github.com/raaf-ai/raaf/blob/main/guides/bug_report_templates/providers.rb)
* [Template for RAAF Memory issues](https://github.com/raaf-ai/raaf/blob/main/guides/bug_report_templates/memory.rb)
* [Template for RAAF Tracing issues](https://github.com/raaf-ai/raaf/blob/main/guides/bug_report_templates/tracing.rb)
* [Template for RAAF Guardrails issues](https://github.com/raaf-ai/raaf/blob/main/guides/bug_report_templates/guardrails.rb)
* [Template for RAAF DSL issues](https://github.com/raaf-ai/raaf/blob/main/guides/bug_report_templates/dsl.rb)
* [Template for RAAF Rails integration issues](https://github.com/raaf-ai/raaf/blob/main/guides/bug_report_templates/rails.rb)
* [Generic template for other issues](https://github.com/raaf-ai/raaf/blob/main/guides/bug_report_templates/generic.rb)

These templates include the boilerplate code to set up a test case. Copy the content of the appropriate template into a `.rb` file and make the necessary changes to demonstrate the issue. You can execute it by running `ruby the_file.rb` in your terminal. If all goes well, you should see your test case failing.

You can then share your executable test case as a [gist](https://gist.github.com) or paste the content into the issue description.

### Special Treatment for Security Issues

WARNING: Please do not report security vulnerabilities with public GitHub issue reports. The [RAAF security policy page](https://github.com/raaf-ai/raaf/blob/main/SECURITY.md) details the procedure to follow for security issues.

### What about Feature Requests?

Please don't put "feature request" items into GitHub Issues. If there's a new
feature that you want to see added to RAAF, you'll need to write the
code yourself - or convince someone else to partner with you to write the code.
Later in this guide, you'll find detailed instructions for proposing a patch to
RAAF. If you enter a wish list item in GitHub Issues with no code, you
can expect it to be marked "invalid" as soon as it's reviewed.

Sometimes, the line between 'bug' and 'feature' is a hard one to draw.
Generally, a feature is anything that adds new behavior, while a bug
is anything that causes incorrect behavior. Sometimes, the Core team will have
to make a judgment call. That said, the distinction generally determines which
patch your change is released with; we love feature submissions! They just
won't get backported to maintenance branches.

If you'd like feedback on an idea for a feature before doing the work to make
a patch, please start a discussion on the [RAAF Discussions](https://github.com/raaf-ai/raaf/discussions). You
might get no response, which means that everyone is indifferent. You might find
someone who's also interested in building that feature. You might get a "This
won't be accepted". But it's the proper place to discuss new ideas. GitHub
Issues are not a particularly good venue for the sometimes long and involved
discussions new features require.


Helping to Resolve Existing Issues
----------------------------------

Beyond reporting issues, you can help the core team resolve existing ones by providing feedback about them. If you are new to RAAF core development, providing feedback will help you get familiar with the mono-repo codebase and the processes.

If you check the [issues list](https://github.com/raaf-ai/raaf/issues) in GitHub Issues, you'll find lots of issues already requiring attention. What can you do about these? Quite a bit, actually:

### Verifying Bug Reports

For starters, it helps just to verify bug reports. Can you reproduce the reported issue on your computer? If so, you can add a comment to the issue saying that you're seeing the same thing.

If an issue is very vague, can you help narrow it down to something more specific? Maybe you can provide additional information to reproduce the bug, or maybe you can eliminate unnecessary steps that aren't required to demonstrate the problem.

If you find a bug report without a test, it's very useful to contribute a failing test. This is also a great way to explore the source code: looking at the existing test files will teach you how to write more tests. New tests are best contributed in the form of a patch, as explained later on in the [Contributing to the RAAF Code](#contributing-to-the-raaf-code) section.

Anything you can do to make bug reports more succinct or easier to reproduce helps folks trying to write code to fix those bugs - whether you end up writing the code yourself or not.

### Testing Patches

You can also help out by examining pull requests that have been submitted to RAAF via GitHub. In order to apply someone's changes, first create a dedicated branch:

```bash
$ git checkout -b testing_branch
```

Then, you can use their remote branch to update your codebase. For example, let's say the GitHub user JohnSmith has forked and pushed to a topic branch "orange" located at https://github.com/JohnSmith/raaf.

```bash
$ git remote add JohnSmith https://github.com/JohnSmith/raaf.git
$ git pull JohnSmith orange
```

An alternative to adding their remote to your checkout is to use the [GitHub CLI tool](https://cli.github.com/) to checkout their pull request.

After applying their branch, test it out! Here are some things to think about:

* Does the change actually work?
* Are you happy with the tests? Can you follow what they're testing? Are there any tests missing?
* Does it have the proper documentation coverage? Should documentation elsewhere be updated?
* Do you like the implementation? Can you think of a nicer or faster way to implement a part of their change?

Once you're happy that the pull request contains a good change, comment on the GitHub issue indicating your findings. Your comment should indicate that you like the change and what you like about it. Something like:

>I like the way you've restructured that code in generate_finder_sql - much nicer. The tests look good too.

If your comment simply reads "+1", then odds are that other reviewers aren't going to take it too seriously. Show that you took the time to review the pull request.

Contributing to the RAAF Documentation
--------------------------------------

Ruby AI Agents Factory has comprehensive documentation: the guides (which help you
learn about RAAF), the API reference, and extensive gem-specific documentation.

You can help improve the RAAF guides or the API reference by making them more coherent, consistent, or readable, adding missing information, correcting factual errors, fixing typos, or bringing them up to date with the latest edge RAAF.

To do so, make changes to RAAF guides source files (located [here](https://github.com/raaf-ai/raaf/tree/main/guides/source) on GitHub) or YARD comments in source code. Then open a pull request to apply your changes to the main branch.

Use `[ci skip]` in your pull request title to avoid running the CI build for documentation changes.

Once you open a PR, a preview of the documentation will be deployed for easy review and collaboration. At the bottom of the Pull Request page, you should see a list of status checks, look for the `buildkite/docs-preview` and click "details".

![GitHub rails/rails Pull Request status checks](images/docs_preview/status_checks.png)

This will bring you to the Buildkite build page. If the job was successful, there will be an annotation with links to the generated API and Guides above the job list.

![Buildkite rails/docs-preview annotation API & Guides links](images/docs_preview/annotation.png)

When working with documentation, please take into account the [API Documentation Guidelines](api_documentation_guidelines.html) and the [RAAF Guides Guidelines](raaf_guides_guidelines.html).

Translating RAAF Guides
-----------------------

We are happy to have people volunteer to translate the RAAF guides. Just follow these steps:

* Fork https://github.com/raaf-ai/raaf.
* Add a source folder for your language, for example: *guides/source/it-IT* for Italian.
* Copy the contents of *guides/source* into your language directory and translate them.
* Do NOT translate the HTML files, as they are automatically generated.

Note that translations are not submitted to the main RAAF repository; your work lives in your fork, as described above. This is because, in practice, documentation maintenance via patches is only sustainable in English.

To generate the guides in HTML format, you will need to install the guides dependencies, `cd` into the *guides* directory, and then run (e.g., for it-IT):

```bash
$ bundle install
$ cd guides/
$ bundle exec rake guides:generate:html GUIDES_LANGUAGE=it-IT
```

This will generate the guides in an *output* directory.

Contributing to the RAAF Code
-----------------------------

### Setting Up a Development Environment

To move on from submitting bugs to helping resolve existing issues or contributing your own code to RAAF, you _must_ be able to run its test suite. In this section of the guide, you'll learn how to set up the tests on your computer.

#### Local Development Requirements

RAaf requires:

* Ruby 3.0+ (Ruby 3.2+ recommended)
* Bundler
* Git
* API keys for testing certain providers (OpenAI, Anthropic, etc.)

#### Using GitHub Codespaces

If you're a member of an organization that has codespaces enabled, you can fork RAAF into that organization and use codespaces on GitHub. The Codespace will be initialized with all required dependencies and allows you to run all tests.

#### Using VS Code Remote Containers

If you have [Visual Studio Code](https://code.visualstudio.com) and [Docker](https://www.docker.com) installed, you can use the [VS Code remote containers plugin](https://code.visualstudio.com/docs/remote/containers-tutorial). Check the repository for a [`.devcontainer`](https://github.com/raaf-ai/raaf/tree/main/.devcontainer) configuration.

#### Local Development Setup

For local development:

1. Clone the repository:
```bash
$ git clone https://github.com/raaf-ai/raaf.git
$ cd raaf
```

2. Install dependencies for all gems:
```bash
$ bundle install
```

3. Set up environment variables:

```bash
$ cp .env.example .env
# Edit .env with your API keys
```

4. Run initial setup:

```bash
$ bundle exec rake setup
```

### Clone the RAAF Repository

To be able to contribute code, you need to clone the RAAF mono-repo:

```bash
$ git clone https://github.com/raaf-ai/raaf.git
```

and create a dedicated branch:

```bash
$ cd raaf
$ git checkout -b my_new_branch
```

It doesn't matter much what name you use because this branch will only exist on your local computer and your personal repository on GitHub. It won't be part of the RAAF Git repository.

### Bundle install

Install the required gems.

```bash
$ bundle install
```

### Testing Changes Against Local RAAF Gems

In case you need to test your changes against a real application, you can use your local RAAF gems. First, in your application's Gemfile, point to your local RAAF mono-repo:

<!-- VALIDATION_FAILED: contributing_to_raaf.md:287 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/dependency.rb:301:in 'Gem::Dependency#to_specs': Could not find 'raaf' (>= 0) among 224 total gem(s) (Gem::MissingSpecError) Checked in 'GEM_PATH=/Users/hajee/.rvm/gems/ruby-3.4.5:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/gems/3.4.0' , execute `gem env` for more information 	from /Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/dependency.rb:313:in 'Gem::Dependency#to_spec' 	from /Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_gem.rb:56:in 'Kernel#gem' 	from /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-yegqo9.rb:445:in '<main>'
```

```ruby
# In your application's Gemfile
gem 'raaf', path: '/path/to/your/raaf'
```

Then run:

```bash
$ bundle install
```

This allows you to test your changes in a real application environment. Any modifications to the RAAF source code will be immediately available to your test application.

### Write Your Code

Now it's time to write some code! When making changes for RAAF, here are some things to keep in mind:

* Follow RAAF style and conventions.
* Use Ruby idioms and maintain consistency with existing RAAF patterns.
* Include tests that fail without your code, and pass with it.
* Update the (surrounding) documentation, examples elsewhere, and the guides: whatever is affected by your contribution.
* If the change adds, removes, or changes a feature, be sure to include a CHANGELOG entry in the relevant gem. If your change is a bug fix, a CHANGELOG entry is not necessary.
* Consider cross-gem impact in the mono-repo when making changes.

TIP: Changes that are cosmetic and do not add anything substantial to the stability, functionality, or testability of RAAF will generally not be accepted.

#### Follow the Coding Conventions

RAAF follows Ruby community coding style conventions:

* Two spaces, no tabs (for indentation).
* No trailing whitespace. Blank lines should not have any spaces.
* Indent and no blank line after private/protected.
* Use modern Ruby syntax. Prefer `{ a: :b }` over `{ :a => :b }`.
* Prefer `&&`/`||` over `and`/`or`.
* Prefer `class << self` over `self.method` for class methods.
* Use `my_method(my_arg)` not `my_method( my_arg )` or `my_method my_arg`.
* Use `a = b` and not `a=b`.
* Use RSpec conventions: `expect().to` instead of `should`.
* Prefer `method { do_stuff }` instead of `method{do_stuff}` for single-line blocks.
* Follow the conventions in the source you see used already.
* Use YARD documentation format for public APIs.

The above are guidelines - please use your best judgment in using them.

Additionally, we have [RuboCop](https://www.rubocop.org/) rules defined to codify some of our coding conventions. You can run RuboCop locally against the file that you have modified before submitting a pull request:

```bash
$ bundle exec rubocop core/lib/raaf/agent.rb
Inspecting 1 file
.

1 file inspected, no offenses detected
```

### Benchmark Your Code

For changes that might have an impact on performance, please benchmark your
code and measure the impact. Please share the benchmark script you used as well
as the results. You should consider including this information in your commit
message to allow future contributors to easily verify your findings and
determine if they are still relevant. (For example, future optimizations in the
Ruby VM might render certain optimizations unnecessary.)

When optimizing for a specific scenario that you care about, it is easy to
regress performance for other common cases.
Therefore, you should test your change against a list of representative
scenarios, ideally based on realistic use cases.

You can use the [benchmark template](https://github.com/raaf-ai/raaf/blob/main/guides/bug_report_templates/benchmark.rb)
as a starting point. It includes the boilerplate code to set up a benchmark
using the [benchmark-ips](https://github.com/evanphx/benchmark-ips) gem. The
template is designed for testing relatively self-contained changes that can be
inlined into the script.

### Running Tests

In RAAF's mono-repo structure, it is not customary to run the full test suite for all gems before pushing
changes. The complete test suite across all 14+ gems takes considerable time.

As a compromise, test what your code obviously affects. If your change is isolated to a specific gem,
run the test suite for that gem. If your change affects multiple gems, run tests for the affected
components. If all tests are passing, that's enough to propose your contribution. We have
CI/CD pipelines as a safety net for catching unexpected breakages elsewhere.

#### Entire RAAF Mono-repo:

To run all tests for all gems, do:

```bash
$ cd raaf
$ bundle exec rake test:all
```

Note: This can take significant time as it runs tests for all 14+ gems.

#### For a Particular Gem

You can run tests only for a particular gem (e.g., RAAF Core). For example,
to run RAAF Core tests:

```bash
$ cd core
$ bundle exec rspec
```

Or to run RAAF Tools tests:

```bash
$ cd tools
$ bundle exec rspec
```

#### For a Specific Directory

You can run tests only for a specific directory of a particular gem
(e.g., agents in RAAF Core). For example, to run tests in `/core/spec/agents`:

```bash
$ cd core
$ bundle exec rspec spec/agents
```

#### For a Specific File

You can run the tests for a particular file:

```bash
$ cd core
$ bundle exec rspec spec/agents/agent_spec.rb
```

#### Running a Single Test

You can run a single test by description or line number:

```bash
$ cd core
$ bundle exec rspec spec/agents/agent_spec.rb -e "creates agent with name"
```

#### For a Specific Line

If you know the line number your test starts at:

```bash
$ cd core
$ bundle exec rspec spec/agents/agent_spec.rb:25
```

#### Running Tests with a Specific Seed

Test execution is randomized with a randomization seed. If you are experiencing random
test failures, you can more accurately reproduce a failing test scenario by specifically
setting the randomization seed:

```bash
$ cd core
$ bundle exec rspec --seed 1234
```

#### Running Tests with Debug Output

For debugging test failures, you can run tests with additional output:

```bash
$ cd core
$ bundle exec rspec --format documentation
```

#### Testing RAAF Memory (Vector Storage)

Some RAAF Memory tests require additional setup for vector databases. Check the gem's README for specific requirements:

```bash
$ cd memory
$ bundle exec rspec
```

#### Testing RAAF Tools

RAaf Tools may require API keys for certain tools (web search, etc.). Set appropriate environment variables:

```bash
$ cd tools
$ OPENAI_API_KEY=your_key bundle exec rspec
```

#### Testing Integration Between Gems

For cross-gem integration tests:

```bash
$ bundle exec rake test:integration
```

#### Using Debuggers with Test

To use an external debugger (pry, byebug, debug, etc), install the debugger and use it as normal.  

For RSpec tests, you can add debugger breakpoints directly:

<!-- VALIDATION_FAILED: contributing_to_raaf.md:489 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NoMethodError: undefined method 'pry' for an instance of Binding /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-218b0v.rb:445:in 'block in <main>' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-218b0v.rb:334:in 'Object#it' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-218b0v.rb:444:in '<main>'
```

```ruby
it "creates an agent" do
  binding.pry  # or binding.break for debug gem
  agent = RAAF::Agent.new(name: "test")
  expect(agent.name).to eq("test")
end
```

### Warnings

The test suite runs with warnings enabled. Ideally, RAAF should issue no warnings, but there may be a few, as well as some from third-party libraries. Please ignore (or fix!) them, if any, and submit patches that do not issue new warnings.

RAAF CI will raise if warnings are introduced. To implement the same behavior locally, set `RAAF_STRICT_WARNINGS=1` when running the test suite.

### Updating the Documentation

The RAAF [guides](https://guides.raaf.ai/) provide a high-level overview of RAAF's features, while the [API documentation](https://api.raaf.ai/) delves into specifics.

If your PR adds a new feature or changes how an existing feature behaves, check the relevant documentation and update it or add to it as necessary.

For example, if you modify RAAF Tools to add a new tool, you should update the [Tools Overview](tools_guide.html) guide to document the new tool and its usage patterns.

### Updating the CHANGELOG

The CHANGELOG is an important part of every release. It keeps the list of changes for every RAAF version.

You should add an entry **to the top** of the CHANGELOG of the gem you modified if you're adding or removing a feature, or adding deprecation notices. Refactorings, minor bug fixes, and documentation changes generally should not go to the CHANGELOG.

A CHANGELOG entry should summarize what was changed and should end with the author's name. You can use multiple lines if you need more space, and you can attach code examples indented with 4 spaces. If a change is related to a specific issue, you should attach the issue's number. Here is an example CHANGELOG entry:

```markdown

*   Summary of a change that briefly describes what was changed. You can use multiple
    lines and wrap them at around 80 characters. Code examples are ok, too, if needed:

        class Foo
          def bar
            puts 'baz'
          end
        end

    You can continue after the code example, and you can attach the issue number.

    Fixes #1234.

    *Your Name*
```

### Breaking Changes

Anytime a change could break existing applications, it's considered a breaking
change. To ease upgrading RAAF applications, breaking changes require a
deprecation cycle.

#### Removing Behavior

If your breaking change removes existing behavior, you'll first need to add a
deprecation warning while keeping the existing behavior.

As an example, let's say you want to remove a public method on
`RAAF::Agent`. If the main branch points to the unreleased 0.2.0 version,
RAAF 0.2.0 will need to show a deprecation warning. This makes sure anyone
upgrading to any RAAF 0.2.0 version will see the deprecation warning.
In RAAF 0.3.0 the method can be deleted.

You could add the following deprecation warning:

```ruby
def deprecated_method
  RAAF.deprecator.warn(<<-MSG.squish)
    `RAAF::Agent.deprecated_method` is deprecated and will be removed in RAAF 0.3.0.
  MSG
  # Existing behavior
end
```

#### Changing Behavior

If your breaking change changes existing behavior, you'll need to add a
framework default. Framework defaults ease RAAF upgrades by allowing apps
to switch to the new defaults one by one.

To implement a new framework default, first create a configuration by adding an
accessor on the target framework. Set the default value to the existing
behavior to make sure nothing breaks during an upgrade.

```ruby
module RAAF
  mattr_accessor :existing_behavior, default: true
end
```

The new configuration allows you to conditionally implement the new behavior:

```ruby
def changed_method
  if RAAF.existing_behavior
    # Existing behavior
  else
    # New behavior
  end
end
```

To set the new framework default, set the new value in
`RAAF::Configuration#load_defaults`:

```ruby
def load_defaults(target_version)
  case target_version.to_s
  when "0.2.0"
    # ...
    RAAF.existing_behavior = false
    # ...
  end
end
```

To ease the upgrade it's required to add the new default to the
`new_framework_defaults` template. Add a commented out section, setting the new
value:

```ruby
# new_framework_defaults_0_2_0.rb.tt

# RAAF.existing_behavior = false
```

As a last step, add the new configuration to configuration guide in
`configuration.md`:

```markdown
#### `RAAF.existing_behavior`

| Starting with version | The default value is |
| --------------------- | -------------------- |
| (original)            | `true`               |
| 0.2.0                 | `false`              |
```

### Ignoring Files Created by Your Editor / IDE

Some editors and IDEs will create hidden files or folders inside the `raaf` folder. Instead of manually excluding those from each commit or adding them to RAAF's `.gitignore`, you should add them to your own [global gitignore file](https://docs.github.com/en/get-started/getting-started-with-git/ignoring-files#configuring-ignored-files-for-all-repositories-on-your-computer).

### Updating the Gemfile.lock

Some changes require dependency upgrades. In these cases, make sure you run `bundle update` to get the correct version of the dependency and commit the `Gemfile.lock` file within your changes.

### Commit Your Changes

When you're happy with the code on your computer, you need to commit the changes to Git:

```bash
$ git commit -a
```

This should fire up your editor to write a commit message. When you have
finished, save, and close to continue.

A well-formatted and descriptive commit message is very helpful to others for
understanding why the change was made, so please take the time to write it.

A good commit message looks like this:

```markdown
Short summary (ideally 50 characters or less)

More detailed description, if necessary. Each line should wrap at
72 characters. Try to be as descriptive as you can. Even if you
think that the commit content is obvious, it may not be obvious
to others. Add any description that is already present in the
relevant issues; it should not be necessary to visit a webpage
to check the history.

The description section can have multiple paragraphs.

Code examples can be embedded by indenting them with 4 spaces:

    class ArticlesController
      def index
        render json: Article.limit(10)
      end
    end

You can also add bullet points:

- make a bullet point by starting a line with either a dash (-)
  or an asterisk (*)

- wrap lines at 72 characters, and indent any additional lines
  with 2 spaces for readability
```

TIP. Please squash your commits into a single commit when appropriate. This
simplifies future cherry picks and keeps the git log clean.

### Update Your Branch

It's pretty likely that other changes to main have happened while you were working. To get new changes in main:

```bash
$ git checkout main
$ git pull --rebase
```

Now reapply your patch on top of the latest changes:

```bash
$ git checkout my_new_branch
$ git rebase main
```

No conflicts? Tests still pass? Change still seems reasonable to you? Then push the rebased changes to GitHub:

```bash
$ git push --force-with-lease
```

We disallow force pushing on the raaf-ai/raaf repository base, but you are able to force push to your fork. When rebasing, this is a requirement since the history has changed.

### Fork

Navigate to the RAAF [GitHub repository](https://github.com/raaf-ai/raaf) and press "Fork" in the upper right-hand corner.

Add the new remote to your local repository on your local machine:

```bash
$ git remote add fork https://github.com/<your username>/raaf.git
```

You may have cloned your local repository from raaf-ai/raaf, or you may have cloned from your forked repository. The following git commands assume that you have made a "raaf" remote that points to raaf-ai/raaf.

```bash
$ git remote add raaf https://github.com/raaf-ai/raaf.git
```

Download new commits and branches from the official repository:

```bash
$ git fetch raaf
```

Merge the new content:

```bash
$ git checkout main
$ git rebase raaf/main
$ git checkout my_new_branch
$ git rebase raaf/main
```

Update your fork:

```bash
$ git push fork main
$ git push fork my_new_branch
```

### Open a Pull Request

Navigate to the RAAF repository you just pushed to (e.g.,
https://github.com/your-user-name/raaf) and click on "Pull Requests" in the top bar (just above the code).
On the next page, click "New pull request" in the upper right-hand corner.

The pull request should target the base repository `raaf-ai/raaf` and the branch `main`.
The head repository will be your work (`your-user-name/raaf`), and the branch will be
whatever name you gave your branch. Click "create pull request" when you're ready.

Ensure the changesets you introduced are included. Fill in some details about
your potential patch, using the pull request template provided. When finished, click "Create
pull request".

### Get Some Feedback

Most pull requests will go through a few iterations before they get merged.
Different contributors will sometimes have different opinions, and often
patches will need to be revised before they can get merged.

Some contributors to RAAF have email notifications from GitHub turned on, but
others do not. Furthermore, (almost) everyone who works on RAAF is a
volunteer, and so it may take a few days for you to get your first feedback on
a pull request. Don't despair! Sometimes it's quick; sometimes it's slow. Such
is the open source life.

If it's been over a week, and you haven't heard anything, you might want to try
and nudge things along. You can use the [RAAF GitHub Discussions](https://github.com/raaf-ai/raaf/discussions)
for this. You can also leave another comment on the pull request. It's best to avoid pinging
individual maintainers directly as we have limited bandwidth and may not
be able to look at your PR.

While you're waiting for feedback on your pull request, open up a few other
pull requests and give someone else some! They'll appreciate it in
the same way that you appreciate feedback on your patches.

Note that only the Core and Committers teams are permitted to merge code changes.
If someone gives feedback and "approves" your changes, they may not have the ability
or final say to merge your change.

### Iterate as Necessary

It's entirely possible that the feedback you get will suggest changes. Don't get discouraged: the whole point of contributing to an active open source project is to tap into the community's knowledge. If people encourage you to tweak your code, then it's worth making the tweaks and resubmitting. If the feedback is that your code won't be merged, you might still think about releasing it as a gem.

#### Squashing Commits

One of the things that we may ask you to do is to "squash your commits", which
will combine all of your commits into a single commit. We prefer pull requests
that are a single commit. This makes it easier to backport changes to stable
branches, squashing makes it easier to revert bad commits, and the git history
can be a bit easier to follow. RAAF is a large project, and a bunch of
extraneous commits can add a lot of noise.

```bash
$ git fetch raaf
$ git checkout my_new_branch
$ git rebase -i raaf/main

< Choose 'squash' for all of your commits except the first one. >
< Edit the commit message to make sense, and describe all your changes. >

$ git push fork my_new_branch --force-with-lease
```

You should be able to refresh the pull request on GitHub and see that it has
been updated.

#### Updating a Pull Request

Sometimes you will be asked to make some changes to the code you have
already committed. This can include amending existing commits. In this
case Git will not allow you to push the changes as the pushed branch
and local branch do not match. Instead of opening a new pull request,
you can force push to your branch on GitHub as described earlier in
squashing commits section:

```bash
$ git commit --amend
$ git push fork my_new_branch --force-with-lease
```

This will update the branch and pull request on GitHub with your new code.
By force pushing with `--force-with-lease`, git will more safely update
the remote than with a typical `-f`, which can delete work from the remote
that you don't already have.

### Older Versions of RAAF

If you want to add a fix to versions of RAAF older than the next release, you'll need to set up and switch to your own local tracking branch. Here is an example to switch to the 0-1-stable branch:

```bash
$ git branch --track 0-1-stable raaf/0-1-stable
$ git checkout 0-1-stable
```

NOTE: Before working on older versions, please check the [maintenance policy](maintenance_policy.html). Changes will not be accepted to versions that have reached end of life.

#### Backporting

Changes that are merged into main are intended for the next major release of RAAF. Sometimes, it might be beneficial to propagate your changes back to stable branches for inclusion in maintenance releases. Generally, security fixes and bug fixes are good candidates for a backport, while new features and patches that change expected behavior will not be accepted. When in doubt, it is best to consult a RAAF team member before backporting your changes to avoid wasted effort.

First, make sure your main branch is up to date.

```bash
$ git checkout main
$ git pull --rebase
```

Check out the branch you're backporting to, for example, `0-1-stable` and make sure it's up to date:

```bash
$ git checkout 0-1-stable
$ git reset --hard origin/0-1-stable
$ git checkout -b my-backport-branch
```

If you're backporting a merged pull request, find the commit for the merge and cherry-pick it:

```bash
$ git cherry-pick -m1 MERGE_SHA
```

Fix any conflicts that occurred in the cherry-pick, push your changes, then open a PR pointing at the stable branch you're backporting to. If you have a more complex set of changes, the [cherry-pick](https://git-scm.com/docs/git-cherry-pick) documentation can help.

RAAF Contributors
-----------------

All contributions get credit in [RAAF Contributors](https://contributors.raaf.ai) and are recognized in the project's contributor documentation.
