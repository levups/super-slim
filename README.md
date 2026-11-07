# SuperSlim

SuperSlim renders [Slim](https://github.com/slim-template/slim) templates in Ruby and Rails apps. Slim is a template
language that writes HTML with indentation instead of closing tags, and SuperSlim is a new engine for it, written
from scratch: your existing `.slim` files produce the same HTML, but they compile about nine times faster and
render about twice as fast.

It also comes with a formatter, a linter and a RuboCop plugin. All three read templates with the engine's own
parser, so they never disagree with it about what a template means.

Website and guide: https://levups.github.io/super-slim/

## Why SuperSlim

A template engine does two jobs. It compiles each template into Ruby code, which Rails does the first time a
template renders and again after you edit it in development. Then it runs that code on every request. SuperSlim
makes both cheaper.

`bench/compare.rb` renders the same blog page (24 post cards) with five engines and checks that they all produce
the same HTML. On the last run (November 2026, Ruby 4.0 with YJIT), SuperSlim compiled the page 9.3 times faster
than Slim and rendered it 2.3 times faster, with a quarter of the allocations:

| Engine | Compiles per second | Renders per second | Objects allocated per render |
|---|---:|---:|---:|
| SuperSlim 1.0.0 | 12,423 | 60,725 | 111 |
| Slim 5.2.2 | 1,341 | 26,786 | 480 |
| Haml 7.5.2 | 1,559 | 37,704 | 471 |
| Herb 0.11.1 | 5,600 | 17,496 | 830 |
| Erubi 1.13.1 (ERB) | 51,144 | 62,746 | 115 |

On whole apps, the 1,399 templates of a production Rails app compile in 108 ms instead of 522 ms, and 6,053
templates from 30 open-source projects in 529 ms instead of 2,472 ms. The linter takes about a third of the CPU
time slim-lint takes on the same templates. The [benchmarks page](https://levups.github.io/super-slim/benchmarks.html)
has the charts and the steps to reproduce them.

## Installation

SuperSlim needs Ruby 3.3 or later. In a Rails app, add it to your Gemfile, and remove `slim-rails` if you have it:
SuperSlim replaces it.

```ruby
gem "super-slim"
```

Rails then renders every `.slim` view with SuperSlim, and the digest of a `cache` block changes when a partial it
renders changes. A partial whose name is computed needs a `/# Template Dependency: orders/line` comment, as in ERB.
There is nothing to configure. Rails itself is optional, and SuperSlim is tested on Rails 8.0 and later.

Without Rails, `SuperSlim.compile` turns a template into Ruby code, which you evaluate where the template's
variables and methods are defined:

```ruby
require "super_slim"

ruby_code = SuperSlim.compile(File.read("page.slim"), file: "page.slim") # file: is shown in errors and backtraces
html = eval(ruby_code, binding)
```

## A first template

```slim
ul.posts
  - posts.each do |post|
    li
      a href=post.url = post.title
      - if post.draft?
        span.badge Draft
```

With two posts, the second one a draft, this renders:

```html
<ul class="posts"><li><a href="/posts/1">Hello &amp; welcome</a></li><li><a href="/posts/2">Next steps</a><span class="badge">Draft</span></li></ul>
```

Lines starting with `-` run Ruby, `=` outputs the result of Ruby code (escaped for HTML), and everything else is a
tag, text or an attribute. The [Slim documentation](https://github.com/slim-template/slim#readme) describes the whole
language. SuperSlim reads all of it, except the few parts listed in [What SuperSlim leaves out](#what-superslim-leaves-out).

## Switching from Slim

SuperSlim renders what Slim renders with the options `format: :html, sort_attrs: false`, byte for byte. Slim's
defaults are different (`format: :xhtml, sort_attrs: true`), so if you never changed them, switch in two steps:

1. Set those two options on Slim and run your test suite. Fix anything that depended on XHTML output or on
   sorted attributes.
2. Replace `slim-rails` with `super-slim` in your Gemfile and remove any `Slim::Engine.set_options` or
   `with_options` call.

Templates for XML formats (`.xml`, `.rss`, `.atom`) render as XML automatically, with `<link />` and
`doctype xml`.

## Formatter

`super-slim format` rewrites templates in one layout: two spaces per level, a space after `-` and `=`, no `div`
where a `.class` or `#id` is enough, no trailing whitespace unless it renders, single blank lines and a final
newline. This template:

```slim
div.card
    -if post.draft?
        span.badge Draft
    =link_to post.title, post


    img src=post.image_url
```

comes out as:

```slim
.card
  - if post.draft?
    span.badge Draft
  = link_to post.title, post

  img src=post.image_url
```

```sh
super-slim format            # every .slim file under the current directory (except .git, node_modules, tmp, vendor)
super-slim format --check    # list the files that would change, and fail if there are any
super-slim format app/views/posts
```

`fmt` is an alias of `format`.

The formatter can't change what a page renders. Before writing a file, it compiles the old and the new version and
compares the Ruby code they produce, using [Prism](https://github.com/ruby/prism). Line breaks, spaces, a trailing
comma or the parentheses of a call may differ. If anything else does, it leaves the file alone and reports it. Text
blocks move together with their whitespace for the same reason.

To also wrap long lines, set a maximum length in `.super-slim.yml`:

```yaml
format:
  max_line_length: 120
  attribute_delimiters: "()" # or "[]" or "{}"
```

The formatter then gives each line one layout, whatever its author chose. Ruby code spread over several lines is
joined back when it fits. A longer line spreads the arguments of its call, or the elements of its array or hash, one
per line, each line but the last ending with a comma:

```slim
= link_to "Read the whole post",
  post_path(post),
  class: "btn btn-primary"
```

Slim, and so Brakeman, reads a line that ends with a comma or a backslash as going on, but not one that ends with an
opening bracket. A call whose only argument is a call spreads that one: `= render Card.new(title: post.title,`. A
first argument that would pass the limit goes to the next line, after a backslash. The lines after the first go two
spaces deep, two more when the line opens a block. Code spread by hand stays as it is when this layout would leave a
line longer than the limit, unless Slim can't read it, and arguments to `new` go in parentheses.

A tag's attributes stand without delimiters when they fit on its line, and one per line inside the delimiters when
they don't, unless its shortcuts alone pass the limit. A literal `id` or `class` becomes a shortcut, a class shortcut
named twice goes, and the other attributes follow one order: `id`, `class`, what the element is (`type`, `name`,
`href`, `src`, `value`, `for`, `action`, `method`), the rest, `data-controller`, `data-action` and targets, other
`data-*`, then `aria-*` and `role`. Delimiters stay around a boolean attribute and before text that would read as
an attribute, and a tag with a `*splat` keeps its order. The formatter takes attribute values to have no side
effects: reordering two Ruby values changes the order they run in.

Lines the formatter should leave alone go between two comments. Without `on`, the rest of the block that holds the
comment stays as written, the rest of the template at the top level. The lines keep their text and only move with
their block, and the lint rules that `super-slim format` would fix stay quiet there:

```slim
table
  / super-slim:format off
  tr: td colspan=8 = t(".empty")
  / super-slim:format on
```

## Linter

```sh
super-slim lint              # every .slim file under the current directory
super-slim lint app/views/posts
```

On the formatted template above, it still finds the image without a text alternative:

```
_card.html.slim:6: [ImageAlt] Describe the image with `alt`, or mark it decorative with `alt=""`
```

The linter reads its settings from `.super-slim.yml`, in the directory you run it from. Its rules come from other
linters, so most will look familiar:

| Rule | Comes from | Default |
|---|---|---|
| Indentation, Tab, TrailingWhitespace, EmptyLines, TrailingBlankLines, ControlStatementSpacing, RedundantDiv | slim-lint (`super-slim format` fixes them) | on |
| LineLength (`max: 120`), CommentControlStatement, EmptyControlStatement, ConsecutiveControlStatements (`max: 2`), TagCase | slim-lint | on |
| InstanceVariables (in partials) | haml-lint, Rails conventions | on |
| StrictLocals (partials declare `/# locals:`) | Rails 7.1 strict locals | off |
| DuplicateId, ImageAlt, IframeTitle, AnchorHref, NestedLinks, PositiveTabindex, BooleanAttributeValue, AriaBooleanValue (`aria-*=true` renders no value, `aria-*=false` no attribute), AriaRole, AriaAttribute | Herb, eslint-plugin-jsx-a11y | on |
| ButtonType, InlineStyles | eslint-plugin-react, haml-lint | off |
| DeprecatedClasses (`classes: {old: new}`, `old-*: new-*` for a prefix), DeprecatedAttributes (`attributes: {old: new}`), both with `preset: bootstrap5` | erb_lint | on, but empty |
| UnescapedOutput (`==`, `html_safe`, `raw`, `#{{}}`) | Brakeman, erb_lint | off |
| SlimSyntax (code continued after an opening bracket, a comment after code: Slim and Brakeman can't read them) | Brakeman | on |
| EmbeddedEngines (`forbidden_engines: [javascript, css]`) | slim-lint | off |
| HardcodedText (text that should be translated) | erb_lint | off |
| UnnecessaryInterpolation, UnnecessaryStringOutput | haml-lint | on |
| Zwsp (invisible characters) | slim-lint | on |

The website shows [each rule with an example](https://levups.github.io/super-slim/tools.html). A configuration
file looks like this:

```yaml
# .super-slim.yml
linters:
  LineLength:
    max: 150
  ButtonType:
    enabled: true
  DeprecatedClasses:
    preset: bootstrap5 # Bootstrap 4 classes that Bootstrap 5.3 renamed or dropped
    classes:
      media: ~ # removes this entry from the preset
      legacy-*: modern-*
  DeprecatedAttributes:
    preset: bootstrap5 # data-toggle becomes data-bs-toggle, and so on
  InlineStyles:
    enabled: true
    exclude: ["app/views/*_mailer/**/*"]
  HardcodedText:
    enabled: true
    include: ["app/views/shop/**/*.slim"]
```

Every rule accepts `include:` and `exclude:`, lists of glob patterns matched against paths relative to
`.super-slim.yml` (`**/` matches any number of directories).

A comment silences rules on the next tag or code line, blank lines and comments skipped, and on the lines it goes on
over. The linter reports a rule name it doesn't know:

```slim
/ super-slim:disable ButtonType, InlineStyles
button style="all: unset" Close
```

The `bootstrap5` preset lists the classes and data attributes that Bootstrap 5.3 renamed, including the ones with
breakpoints such as `text-md-right`. Its data attributes are only those of Bootstrap's own components
(`data-toggle`, `data-target` and the like). If your app also uses generic ones such as `data-content`, add them
under `attributes:`. If your own JavaScript still reads an attribute the preset renames, remove that entry with `~`.

## RuboCop plugin

The linter checks the Slim side of a template. For the Ruby inside it, SuperSlim has a RuboCop plugin, which
replaces rubocop-slim (and with it slimi and Temple). It passes every `-` and `=` line, Ruby attribute, splat,
`#{}` interpolation and `ruby:` block to RuboCop. Offenses point at the right line and column of the `.slim` file,
and `rubocop -a` writes its corrections back into it.

```yaml
# .rubocop-slim.yml, run with: rubocop -c .rubocop-slim.yml
inherit_from: .rubocop.yml
plugins:
  - super-slim
AllCops:
  Include:
    - "**/*.slim"
```

Some cops make no sense inside a template, such as indentation and alignment across lines, the frozen string
comment, or `Lint/UselessAssignment` on a variable that a later line uses. The plugin turns them off for `.slim`
files, as rubocop-slim does. SuperSlim also reads code that slimi skips, for example the output of a tag with
attributes and whitespace markers (`span> title="x" = name`), so you may see a few new offenses after switching.

## Additions to Slim

Three additions read templates that Slim refuses or misreads. None changes a template that already works with
Slim.

### Ruby code over several lines

Slim lets a line of Ruby continue on the next line after a comma or a backslash. SuperSlim also continues it after
an opening `(`, `[` or `{` at the end of a line, until the bracket is closed:

```slim
= render ProductCardComponent.new(
    product:,
    variant: :compact,
  )
- columns = %w[
    name
    price
  ]
```

A bracket opened in the middle of a line, as in `- items.each { |item|`, works as before: the lines below it are
its children.

### Comments after Ruby code

Slim compiles `= render CardComponent.new(post:) # rubocop:disable Some/Cop -- reason` into a syntax error: the
comment swallows the parenthesis that closes the output, or the `do` of a block. SuperSlim leaves a comment that
follows code on its line out of the compiled Ruby, after `=`, `==` and `-` alike, so a RuboCop directive can sit on
the line it is about.
Slim still can't read such a template, and neither can Brakeman, which parses views with Slim: it reports the
template as an error and checks nothing in it. The `SlimSyntax` linter rule flags these lines; turn it off if you
don't run Brakeman.

### Tailwind class names

Slim stops a `.class` shortcut at characters such as `[`, `:` or `/`, which Tailwind uses all the time. It renders
`.size-2.5` as `class="size-2 5"`, and refuses `.lg:[&:nth-child(3)]:hover:underline`. With `tailwind_classes` on,
the shortcut takes any Tailwind class name:

```slim
.p-1.rounded-b-[3px].lg:[&:nth-child(3)]:hover:underline
.font-['Open_Sans'].bg-(--brand).mx-0.5.w-1/2.!font-bold.@lg:flex
ul.*:p-2
```

Turn it on for the engine, in `config/initializers/super_slim.rb` for example (or per call with
`SuperSlim.compile(source, tailwind_classes: true)`):

```ruby
SuperSlim.tailwind_classes = true
```

And for the formatter and the linter, in `.super-slim.yml`:

```yaml
tailwind_classes: true
```

Everything else reads as before. Tailwind never puts a bracket right after a letter or a digit, so in
`a.btn[href="/"]` the brackets are still an attribute list. `li.item: a` still nests a tag, and a final `/` still
closes one. On 7,505 templates from 31 apps, 16 compiled differently with the option on, and each time it was a
Tailwind class that Slim broke. The option is off by default anyway, so that switching to SuperSlim changes
nothing. It costs nothing measurable: compile time on 1,408 templates moved by 0.5%, within noise, and the
compiled code is the same, so render time is too.

## Escaping

Like Slim, SuperSlim escapes for HTML everything that `=`, `#{}` and attribute values output. `==` and `#{{}}`
output raw HTML, so only use them on content you trust. In Rails, strings marked `html_safe` aren't escaped again.

Some names are only known when the page renders: the keys of a `*splat` hash, of a `data:` or `aria:` hash, and
the tag of `*{tag: …}`. SuperSlim checks those names and raises an error instead of rendering one that would break
the HTML. Slim does not check them. With Slim, `data: {"x\tonclick" => code}` renders an `onclick` attribute, and
`*{tag: "img src=x onerror=…"}` renders an image with an `onerror` handler. SuperSlim raises
`SuperSlim::InvalidAttributeNameError` and `SuperSlim::InvalidTagNameError` instead.

HTML escaping protects HTML, and nothing else. A `#{}` of user input inside `javascript:` or `css:`, inside an
unquoted attribute of inline HTML, or in the URL of a `markdown:` link can still inject code. In scripts, write
`#{{json_escape(value.to_json)}}` (Rails), always quote attributes, and check URLs before they reach a template.

## What SuperSlim leaves out

These parts of Slim aren't supported. Each one fails when the template compiles, with an error that names it:

- the XHTML format, the `sort_attrs`, `attr_quote`, `pretty` and `js_wrapper` options, and every Temple option;
- the `coffee:`, `sass:`, `scss:`, `less:`, `erb:`, `builder:`, `textile:`, `rdoc:`, `asciidoc:` and wiki
  engines, and `/[if IE]` conditional comments;
- the `logic_less`, `translator`, `include` and `smart` plugins, and custom shortcuts (only `#id` and `.class`
  exist).

The embedded engines that do work are `ruby:`, `javascript:`, `css:` and `markdown:`. `markdown:` uses
[Markly](https://github.com/ioquatix/markly), so add `gem "markly"` to your Gemfile if you use it. The rest can
come back if people ask for them, as long as they don't slow down rendering.

## Learn more

The website has a [guide](https://levups.github.io/super-slim/guide.html) with every option, a page on the
[formatter and linter](https://levups.github.io/super-slim/tools.html) with an example for each rule, the
[benchmarks](https://levups.github.io/super-slim/benchmarks.html) and the
[test setup](https://levups.github.io/super-slim/testing.html). [CHANGELOG.md](CHANGELOG.md) lists the changes in
each version.

## How it is tested

Slim is the reference. Its own test suite, including the examples of its specification (`TESTS.md`), runs against
SuperSlim: every template is rendered by both engines, and the HTML has to match.

On top of that:

- A fuzzer builds thousands of random templates from the grammar and compares the output of both engines. CI runs
  10,000 new ones on every build.
- Snapshots in `test/golden` record the HTML, the compiled Ruby, the formatted template and the lint offenses for
  templates covering the whole grammar, its errors and Tailwind class names. `UPDATE_GOLDEN=1` rewrites them after
  a deliberate change.
- `bench/compiled_digests.rb` checks that a refactoring leaves the compiled Ruby of a whole set of templates
  unchanged.

Real templates come from 30 open-source apps, pinned to a commit in `corpus/manifest.yml`. `rake corpus:fetch`
downloads only their `.slim` files, into `corpus/cache` (ignored by Git). `rake corpus:check` compiles, formats
and lints each of them and compares the result with Slim. `rake corpus:diff BASE=rev` shows what a change does to
them: compiled Ruby, formatting and lint offenses. These templates are never rendered, because rendering would run
their Ruby code. Your own templates can be rendered too: pass their directories in `SUPER_SLIM_CORPUS`.

## Development

```sh
bundle install
bundle exec rake test                                            # SuperSlim's tests, then Slim's own suites
BUNDLE_GEMFILE=gemfiles/rails_8_0.gemfile bundle exec rake test  # the same on Rails 8.0
bundle exec rubocop
FUZZ_SEED=42 FUZZ_CASES=20000 bundle exec ruby -Ilib -Itest test/fuzz_test.rb
bundle exec ruby -Ilib bench/corpus.rb path/to/app               # compile time and allocations against Slim
bundle exec ruby --yjit -Ilib bench/render.rb                    # render speed and allocations against Slim
bundle exec rake docs                                            # rebuild the linter rules page of the website
```

The website's numbers come from `docs/benchmarks.json`, which `rake bench` rewrites by running `bench/compare.rb`.
If `corpus/cache` is there, it also times the open-source templates, and compares `super-slim lint` and `format`
with slim-lint when slim-lint is installed. Run it on a quiet machine:

```sh
bundle exec rake bench                                       # with YJIT, 5 seconds per measurement
SUPER_SLIM_CORPUS=path/to/app/views bundle exec rake bench   # also times compiling a whole app against Slim
BENCH_LOCK=path/to/.bench.lock bundle exec rake bench        # waits while another benchmark holds the lock
```

[CONTRIBUTING.md](CONTRIBUTING.md) explains how to propose a change. Please report security issues privately, as
[SECURITY.md](SECURITY.md) describes.

### Releasing

Pull requests don't touch `CHANGELOG.md`. A release starts by writing its notes under `## [Unreleased]`, from the
pull requests merged since the last tag, without committing them. Refresh the numbers on the website first, on a
quiet machine (`SUPER_SLIM_CORPUS=path/to/app/views bundle exec rake bench`), and merge them in their own pull
request. Then, from an up-to-date `main` with green CI:

```sh
bin/release minor --dry-run   # shows the notes and the changes, writes nothing
bin/release minor             # or patch, major, or an exact version such as 1.2.0
```

Nobody pushes to `main` directly, so `bin/release` dates the Unreleased section and bumps the version on a
`release/vX.Y.Z` branch, opens a pull request that merges itself once CI passes, and waits for it. It then pushes
a signed `vX.Y.Z` tag on the merge commit (if you stopped it while it waited, `bin/release --tag X.Y.Z` does that
step). The tag starts the Release workflow, which publishes the gem to RubyGems through trusted publishing and
creates the GitHub release with the notes and the `.gem` file.

## License

MIT, by [Level UP Solutions](https://github.com/levups). The parser follows the grammar and the parsing algorithm
of [Slim](https://github.com/slim-template/slim), by the Slim Team (MIT).
