# frozen_string_literal: true

# Runs every example below through the linter, fails if an example lies (a flagged one that passes, a clean one
# that does not), then rewrites the linter rules block of docs/tools.html with the real messages.
#   rake docs
require "cgi"
require "super_slim"
require "super_slim/linter"

PAGE_PATH = File.expand_path("../docs/tools.html", __dir__)
abort "Linter::RULES_URL does not point at #{File.basename(PAGE_PATH)}" unless SuperSlim::Linter::RULES_URL.end_with?("/#{File.basename(PAGE_PATH)}")
RULES_BLOCK = /(<!-- linter-rules -->\n).*(<!-- \/linter-rules -->)/m
RULE_COUNT = %r{(<span id="rule-count">)\d+(</span>)}
OFF_BY_DEFAULT = /(# off by default: )[A-Za-z]+(?:, [A-Za-z]+)*/

Example = Data.define(:flagged, :clean, :path) do
  def initialize(flagged:, clean:, path: "show.html.slim") = super
end

EXAMPLE_BY_RULE = {
  "Indentation" => Example.new("ul\n   li Home\n", "ul\n  li Home\n"),
  "Tab" => Example.new("ul\n\tli Home\n", "ul\n  li Home\n"),
  "TrailingWhitespace" => Example.new("ul \n  li Home\n", "ul\n  li Home\n"),
  "EmptyLines" => Example.new("h1 Title\n\n\np Text\n", "h1 Title\n\np Text\n"),
  "TrailingBlankLines" => Example.new("p Text\n\n", "p Text\n"),
  "ControlStatementSpacing" => Example.new("-if admin?\n  p Admin\n", "- if admin?\n  p Admin\n"),
  "RedundantDiv" => Example.new("div.card\n  p Text\n", ".card\n  p Text\n"),
  "LineLength" => Example.new("p #{"word " * 25}\n", "p\n  | #{("word " * 10).strip}\n"),
  "CommentControlStatement" => Example.new("- # TODO\np Text\n", "/ TODO\np Text\n"),
  "EmptyControlStatement" => Example.new("-\np Text\n", "p Text\n"),
  "ConsecutiveControlStatements" => Example.new("- a = 1\n- b = 2\n- c = 3\np = a + b + c\n",
    "ruby:\n  a = 1\n  b = 2\n  c = 3\np = a + b + c\n"),
  "TagCase" => Example.new("P Text\n", "p Text\n"),
  "Zwsp" => Example.new("p Hello​world\n", "p Hello world\n"),
  "UnnecessaryInterpolation" => Example.new("p \#{post.title}\n", "p = post.title\n"),
  "UnnecessaryStringOutput" => Example.new("p\n  = \"Hello\"\n", "p\n  | Hello\n"),
  "DeprecatedClasses" => Example.new("p.text-muted Text\n", "p.text-body-secondary Text\n"),
  "DeprecatedAttributes" => Example.new("button data-toggle=\"modal\" type=\"button\" Open\n",
    "button data-bs-toggle=\"modal\" type=\"button\" Open\n"),
  "UnescapedOutput" => Example.new("p == post.intro\n", "p = t(\".intro_html\")\n"),
  "SlimSyntax" => Example.new("= render Card.new(post:) # the card of the post\n", "/ The card of the post\n= render Card.new(post:)\n"),
  "EmbeddedEngines" => Example.new("javascript:\n  track(\"view\")\n", "div data-controller=\"tracking\"\n"),
  "HardcodedText" => Example.new("h1 Welcome\n", "h1 = t(\".welcome\")\n", "shop/show.html.slim"),
  "InlineStyles" => Example.new("p style=\"color: red\" Text\n", "p.text-danger Text\n"),
  "InlineEventHandlers" => Example.new("select name=\"sort\" onchange=\"this.form.requestSubmit()\"\n",
    "select name=\"sort\" data-action=\"sort#submit\"\n"),
  "InstanceVariables" => Example.new("p = @post.title\n", "/# locals: (post:)\np = post.title\n", "_card.html.slim"),
  "StrictLocals" => Example.new("p = post.title\n", "/# locals: (post:)\np = post.title\n", "_card.html.slim"),
  "DuplicateId" => Example.new("#menu\n#menu\n", "#menu\n#footer-menu\n"),
  "ImageAlt" => Example.new("img src=post.image_url\n", "img src=post.image_url alt=post.title\n"),
  "IframeTitle" => Example.new("iframe src=video_url\n", "iframe src=video_url title=\"Intro video\"\n"),
  "AnchorHref" => Example.new("a href=\"#\" data-action=\"comments#add\" Add a comment\n",
    "button data-action=\"comments#add\" type=\"button\" Add a comment\n"),
  "NestedLinks" => Example.new("a href=\"/a\"\n  a href=\"/b\" B\n", "a href=\"/a\" A\na href=\"/b\" B\n"),
  "PositiveTabindex" => Example.new("button tabindex=\"3\" type=\"button\" Save\n", "button tabindex=\"0\" type=\"button\" Save\n"),
  "BooleanAttributeValue" => Example.new("input disabled=\"disabled\"\n", "input disabled=true\n"),
  "AriaBooleanValue" => Example.new(".toast aria-atomic=true\n", ".toast aria-atomic=\"true\"\n"),
  "AriaRole" => Example.new("div role=\"buton\"\n", "div role=\"button\"\n"),
  "AriaAttribute" => Example.new("button aria-lable=\"Close\" type=\"button\"\n", "button aria-label=\"Close\" type=\"button\"\n"),
  "ButtonType" => Example.new("button Save\n", "button type=\"submit\" Save\n")
}.freeze

RULES_BY_GROUP = {
  "Layout" =>
    %w[Indentation Tab TrailingWhitespace EmptyLines TrailingBlankLines ControlStatementSpacing RedundantDiv],
  "Template hygiene, from slim-lint" =>
    %w[LineLength CommentControlStatement EmptyControlStatement ConsecutiveControlStatements TagCase Zwsp],
  "Ruby in templates, from haml-lint and erb_lint" =>
    %w[UnnecessaryInterpolation UnnecessaryStringOutput DeprecatedClasses DeprecatedAttributes InlineStyles InlineEventHandlers UnescapedOutput
      SlimSyntax EmbeddedEngines HardcodedText],
  "Rails conventions" => %w[InstanceVariables StrictLocals],
  "HTML and accessibility, from Herb and jsx-a11y" =>
    %w[DuplicateId ImageAlt IframeTitle AnchorHref NestedLinks PositiveTabindex BooleanAttributeValue AriaBooleanValue AriaRole AriaAttribute ButtonType]
}.freeze

# Why the rule exists, in one or two sentences: the message says what to do, this says what goes wrong otherwise.
WHY_BY_RULE = {
  "Indentation" => "Slim reads a template's structure from its indentation: one width everywhere keeps the nesting easy to see.",
  "Tab" => "A tab is as wide as each editor wants, so nesting that looks right in one looks wrong in another.",
  "TrailingWhitespace" => "Invisible characters that only show up in diffs. At the end of text, Slim outputs them: " \
    "`super-slim format` leaves those, and the rule asks to write the space with `'` or `>`.",
  "EmptyLines" => "One empty line is enough to separate two blocks.",
  "TrailingBlankLines" => "A file ends with one newline: empty lines after it only show up in diffs.",
  "ControlStatementSpacing" => "`- if` then reads like `= value` and `| text`: the marker, a space, the content.",
  "RedundantDiv" => "A `.class` or `#id` shortcut without a tag name already makes a `div`.",
  "LineLength" => "The end of a long line hides past the edge of the editor and of a diff. " \
    "`super-slim format` wraps attribute lists when `format.max_line_length` is set.",
  "CommentControlStatement" => "A `- #` comment goes into the compiled Ruby, while a `/` comment is dropped at compile time.",
  "EmptyControlStatement" => "A lone `-` runs nothing: it is a leftover from an edit.",
  "ConsecutiveControlStatements" => "A run of `-` lines is a block of Ruby: a `ruby:` block shows it as one, " \
    "and makes it plain when it belongs in a helper.",
  "TagCase" => "HTML tag names are lowercase by convention. SVG tags such as `foreignObject` are left alone.",
  "Zwsp" => "Zero-width characters, often pasted from a document, are invisible in the editor but break searches, " \
    "links and line wrapping. The joiners inside emoji such as 👩🏻‍💻 are left alone.",
  "UnnecessaryInterpolation" => "`\#{}` around the whole text is an output in disguise: `=` says it plainly.",
  "UnnecessaryStringOutput" => "Outputting a string literal runs Ruby for text that `|` writes as it is.",
  "DeprecatedClasses" => "A class your CSS framework renamed or dropped stops styling the page without an error. " \
    "List them under `classes:`, or start from the `bootstrap5` preset.",
  "DeprecatedAttributes" => "The same for data attributes: Bootstrap 5 reads `data-bs-toggle`, " \
    "so a `data-toggle` left over from Bootstrap 4 no longer opens anything.",
  "InlineStyles" => "A `style` attribute cannot be reused or changed by a media query, " \
    "and a strict Content Security Policy blocks it.",
  "InlineEventHandlers" => "An `on*` attribute such as `onchange` runs JavaScript written in the page, " \
    "which a strict Content Security Policy blocks: the handler silently does nothing.",
  "UnescapedOutput" => "`==`, `html_safe`, `raw` and `\#{{}}` output a string as HTML: " \
    "if any of it comes from a user, it is a cross-site scripting hole.",
  "SlimSyntax" => "SuperSlim reads these lines, Slim does not. Brakeman parses templates with Slim: " \
    "it reports such a template as an error and checks none of its Ruby.",
  "EmbeddedEngines" => "Inline JavaScript and CSS are sent again with every page, cached nowhere, " \
    "and blocked by a strict Content Security Policy.",
  "HardcodedText" => "Text written in the template cannot be translated. " \
    "Turn the rule on with `include:` for the parts of the app that are translated.",
  "InstanceVariables" => "A partial that reads instance variables depends on the controller that renders it: " \
    "locals say what it needs. Checked in partials only.",
  "StrictLocals" => "With a `locals:` comment, Rails 7.1 and later raise when a partial gets a local it does not " \
    "declare, or misses a required one.",
  "DuplicateId" => "An `id` names one element of the page: labels, anchors, ARIA references and " \
    "`getElementById` all find the first one only.",
  "ImageAlt" => "Screen readers read `alt` in place of the image, and the file name without it. " \
    "An empty `alt` tells them to skip a decorative image.",
  "IframeTitle" => "Screen readers announce a frame by its `title`, so that users know what is inside before entering it.",
  "AnchorHref" => "A link without `href` cannot be reached with the keyboard and is not announced as a link. " \
    "One to `#` or to a `javascript:` URL is a button in disguise: screen readers announce a link, and opening it in a new tab leads nowhere.",
  "NestedLinks" => "HTML forbids a link inside a link: browsers close the first one early, " \
    "and the page is not built as written.",
  "PositiveTabindex" => "A positive `tabindex` moves the element ahead of everything else in keyboard order, " \
    "away from where it stands on the screen.",
  "BooleanAttributeValue" => "In Slim, `true` renders a boolean attribute and `false` leaves it out, " \
    "while any string renders it: `disabled=\"false\"` disables.",
  "AriaBooleanValue" => "ARIA states are the strings `\"true\"` and `\"false\"`: Slim renders `aria-*=true` " \
    "without a value and leaves out `aria-*=false`.",
  "AriaRole" => "Assistive technologies ignore a role they do not know, so a typo drops the meaning you added.",
  "AriaAttribute" => "Assistive technologies ignore an `aria-*` attribute they do not know, so a typo does nothing.",
  "ButtonType" => "A `button` without `type` submits its form: saying `button` or `submit` avoids a submission " \
    "nobody meant."
}.freeze

# What the rule checks, a few words for the table of rules.
SUMMARY_BY_RULE = {
  "Indentation" => "Two spaces per level",
  "Tab" => "No tabs in indentation",
  "TrailingWhitespace" => "No whitespace at the end of a line",
  "EmptyLines" => "No more than one empty line in a row",
  "TrailingBlankLines" => "No empty lines at the end of the file",
  "ControlStatementSpacing" => "A space after `-`",
  "RedundantDiv" => "No `div` before a `.class` or `#id` shortcut",
  "LineLength" => "Lines of at most 120 characters, by default",
  "CommentControlStatement" => "Comments with `/`, not `- #`",
  "EmptyControlStatement" => "No lone `-`",
  "ConsecutiveControlStatements" => "A `ruby:` block for runs of `-` lines",
  "TagCase" => "Lowercase tag names",
  "Zwsp" => "No invisible zero-width characters",
  "UnnecessaryInterpolation" => "`=` rather than text that only interpolates",
  "UnnecessaryStringOutput" => "`|` rather than outputting a string literal",
  "DeprecatedClasses" => "Classes your CSS framework renamed",
  "DeprecatedAttributes" => "Data attributes your framework renamed",
  "InlineStyles" => "No `style` attributes",
  "InlineEventHandlers" => "No `onclick`, `onchange` and other `on*` attributes",
  "UnescapedOutput" => "No output that skips HTML escaping",
  "SlimSyntax" => "Only lines Slim and Brakeman can read",
  "EmbeddedEngines" => "No `javascript:` or `css:` blocks you forbid",
  "HardcodedText" => "Text goes through translations",
  "InstanceVariables" => "Partials take locals, not instance variables",
  "StrictLocals" => "Partials declare their locals",
  "DuplicateId" => "Each `id` once per template",
  "ImageAlt" => "Images have `alt`",
  "IframeTitle" => "Frames have `title`",
  "AnchorHref" => "Links have `href`, and it goes somewhere",
  "NestedLinks" => "No link inside a link",
  "PositiveTabindex" => "No positive `tabindex`",
  "BooleanAttributeValue" => "Boolean attributes take `true` or `false`",
  "AriaBooleanValue" => "ARIA states are strings",
  "AriaRole" => "Roles that exist",
  "AriaAttribute" => "`aria-*` attributes that exist",
  "ButtonType" => "Buttons have `type`"
}.freeze

# What each option of a rule's DEFAULTS holds, printed beside its default value.
NOTE_BY_OPTION = {
  "LineLength.max" => "the longest line, in characters",
  "ConsecutiveControlStatements.max" => "lines of `-` in a row before asking for a `ruby:` block",
  "DeprecatedClasses.classes" => "`old: new`, or `old-*: new-*` for a prefix; `old: ~` drops an entry of the preset",
  "DeprecatedAttributes.attributes" => "`old: new`; `old: ~` drops an entry of the preset",
  "EmbeddedEngines.forbidden_engines" => "the engines to flag, such as `[javascript, css]`"
}.freeze

rule_names = SuperSlim::Linter::Rules.all.map(&:rule_name)
undocumented = rule_names - EXAMPLE_BY_RULE.keys
abort "Rules without an example: #{undocumented.join(", ")}" if undocumented.any?
ungrouped = EXAMPLE_BY_RULE.keys - RULES_BY_GROUP.values.flatten
abort "Rules without a group: #{ungrouped.join(", ")}" if ungrouped.any?
unexplained = rule_names - WHY_BY_RULE.keys
abort "Rules without a why: #{unexplained.join(", ")}" if unexplained.any?
unsummarized = rule_names - SUMMARY_BY_RULE.keys
abort "Rules without a summary: #{unsummarized.join(", ")}" if unsummarized.any?

rule_class_by_name = SuperSlim::Linter::Rules.all.to_h { [_1.rule_name, _1] }
options_by_rule = rule_class_by_name.transform_values { _1::DEFAULTS.except(:enabled).transform_keys(&:to_s) }
unnoted = options_by_rule.flat_map { |rule, options| options.keys.map { "#{rule}.#{_1}" } } - NOTE_BY_OPTION.keys
abort "Options without a note: #{unnoted.join(", ")}" if unnoted.any?
presets_by_rule = SuperSlim::Linter::PRESETS.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(preset, options_by_rule_name), presets|
  options_by_rule_name.each_key { presets[_1] << preset }
end

off_by_default = rule_names.reject { rule_class_by_name.fetch(_1)::DEFAULTS[:enabled] }
linter = SuperSlim::Linter.new(
  off_by_default.to_h { [_1, {"enabled" => true}] }.merge(
    "DeprecatedClasses" => {"classes" => {"text-muted" => "text-body-secondary"}},
    "DeprecatedAttributes" => {"attributes" => {"data-toggle" => "data-bs-toggle"}},
    "EmbeddedEngines" => {"enabled" => true, "forbidden_engines" => ["javascript"]},
    "HardcodedText" => {"enabled" => true, "include" => ["shop/*"]}
  )
)
message_by_rule = EXAMPLE_BY_RULE.to_h do |rule, example|
  flagged = linter.call(example.path, example.flagged).find { _1.rule == rule }
  abort "#{rule}: the flagged example passes" unless flagged
  clean_offenses = linter.call(example.path, example.clean)
  abort "#{rule}: the clean example is flagged: #{clean_offenses.map(&:message).join(", ")}" if clean_offenses.any?

  [rule, flagged.message]
end

# Measured, not declared: the rule is fixed by the formatter when the formatted flagged example passes it.
formatter = SuperSlim::Formatter.new
fixed_by_format = EXAMPLE_BY_RULE.select do |rule, example|
  linter.call(example.path, formatter.call(example.flagged)).none? { _1.rule == rule }
rescue SuperSlim::Error
  false
end.keys
layout_rules = RULES_BY_GROUP.fetch("Layout")
abort "In the layout group but not fixed by super-slim format: #{(layout_rules - fixed_by_format).join(", ")}" unless (layout_rules - fixed_by_format).empty?

def escape(text) = CGI.escapeHTML(text)

def with_code(text) = escape(text).gsub(/`([^`]+)`/) { "<code>#{$1}</code>" }

def setting(value)
  case value
  when true, false, Integer, nil then value.inspect.sub("nil", "none")
  when Hash, Array then value.empty? ? value.inspect : abort("No default shown for a non-empty #{value.inspect}")
  else abort "No default shown for #{value.inspect}"
  end
end

def settings_table(rule, enabled, options, presets)
  rows = [["enabled", enabled, "`true` runs the rule, `false` turns it off"]]
  rows.concat(options.map { |option, value| [option, value, NOTE_BY_OPTION.fetch("#{rule}.#{option}")] })
  rows << ["preset", nil, "adds a list under your own entries: #{presets.map { "`#{_1}`" }.join(", ")}"] if presets.any?
  body = rows.map do |option, value, note|
    "<tr><td><code>#{option}</code></td><td><code>#{escape(setting(value))}</code></td><td>#{with_code(note)}</td></tr>"
  end
  %(<table class="rule-settings"><thead><tr><th scope="col">Setting</th><th scope="col">Default</th>) +
    %(<th scope="col">Meaning</th></tr></thead><tbody>#{body.join}</tbody></table>)
end

def visible_source(rule, source)
  source = source.gsub(/ +$/) { "·" * _1.size } if rule == "TrailingWhitespace"
  source.gsub("\t", "→   ").gsub("​", "\\u200B")
end

index_rows = RULES_BY_GROUP.map do |title, rules|
  rows = rules.map do |rule|
    default = off_by_default.include?(rule) ? "off" : "on"
    fixed = fixed_by_format.include?(rule) ? "yes" : ""
    %(<tr><td><a href="##{rule}">#{rule}</a></td><td>#{with_code(SUMMARY_BY_RULE.fetch(rule))}</td>) +
      %(<td class="#{default}">#{default}</td><td>#{fixed}</td></tr>\n)
  end
  %(<tr class="rule-index-group"><th colspan="4" scope="rowgroup">#{title}</th></tr>\n#{rows.join})
end
index_html = <<~HTML
  <table class="rule-index">
  <thead><tr><th scope="col">Rule</th><th scope="col">Checks</th><th scope="col">Default</th><th scope="col">Fixed by format</th></tr></thead>
  <tbody>
  #{index_rows.join}</tbody>
  </table>
HTML

rules_html = RULES_BY_GROUP.map do |title, rules|
  items = rules.map do |rule|
    example = EXAMPLE_BY_RULE.fetch(rule)
    enabled = !off_by_default.include?(rule)
    badges = [enabled ? %(<span class="badge on">On by default</span>) : %(<span class="badge off">Off by default</span>)]
    badges << %(<span class="badge">Fixed by <code>super-slim format</code></span>) if fixed_by_format.include?(rule)
    <<~HTML
      <article class="rule" id="#{rule}">
        <h4><a href="##{rule}">#{rule}</a></h4>
        <p class="rule-badges">#{badges.join}</p>
        <p class="rule-why">#{with_code(WHY_BY_RULE.fetch(rule))}</p>
        <div class="rule-examples">
          <div><p class="example-label">Flagged</p><pre><code class="language-slim">#{escape(visible_source(rule, example.flagged))}</code></pre><p class="rule-output">#{with_code(message_by_rule.fetch(rule))}</p></div>
          <div><p class="example-label">Clean</p><pre><code class="language-slim">#{escape(example.clean)}</code></pre></div>
        </div>
        #{settings_table(rule, enabled, options_by_rule.fetch(rule), presets_by_rule[rule])}
      </article>
    HTML
  end
  %(<section class="rule-group"><h3>#{title}</h3>\n#{items.join}</section>\n)
end.join

page = File.read(PAGE_PATH)
abort "No <!-- linter-rules --> block in #{PAGE_PATH}" unless page.match?(RULES_BLOCK)
abort "No rule-count span in #{PAGE_PATH}" unless page.match?(RULE_COUNT)
abort "No `# off by default:` comment in #{PAGE_PATH}" unless page.match?(OFF_BY_DEFAULT)
page = page.sub(RULES_BLOCK) { "#{$1}#{index_html}#{rules_html}#{$2}" }.sub(RULE_COUNT) { "#{$1}#{EXAMPLE_BY_RULE.size}#{$2}" }
  .sub(OFF_BY_DEFAULT) { "#{$1}#{off_by_default.sort.join(", ")}" }
File.write(PAGE_PATH, page)
puts "#{EXAMPLE_BY_RULE.size} rules written to #{PAGE_PATH}"
