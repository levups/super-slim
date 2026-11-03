# frozen_string_literal: true

# Runs every example below through the linter, fails if an example lies (a flagged one that passes, a clean one
# that does not), then rewrites the linter rules block of docs/tools.html with the real messages.
#   rake docs
require "cgi"
require "slimx"
require "slimx/linter"

PAGE_PATH = File.expand_path("../docs/tools.html", __dir__)
RULES_BLOCK = /(<!-- linter-rules -->\n).*(<!-- \/linter-rules -->)/m
RULE_COUNT = %r{(<span id="rule-count">)\d+(</span>)}

Example = Data.define(:flagged, :clean, :path) do
  def initialize(flagged:, clean:, path: "show.html.slim") = super
end

EXAMPLE_BY_RULE = {
  "Indentation" => Example.new("ul\n   li Home\n", "ul\n  li Home\n"),
  "Tab" => Example.new("ul\n\tli Home\n", "ul\n  li Home\n"),
  "TrailingWhitespace" => Example.new("p Hello \n", "p Hello\n"),
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
  "InlineStyles" => Example.new("p style=\"color: red\" Text\n", "p.text-danger Text\n"),
  "InstanceVariables" => Example.new("p = @post.title\n", "/# locals: (post:)\np = post.title\n", "_card.html.slim"),
  "StrictLocals" => Example.new("p = post.title\n", "/# locals: (post:)\np = post.title\n", "_card.html.slim"),
  "DuplicateId" => Example.new("#menu\n#menu\n", "#menu\n#footer-menu\n"),
  "ImageAlt" => Example.new("img src=post.image_url\n", "img src=post.image_url alt=post.title\n"),
  "IframeTitle" => Example.new("iframe src=video_url\n", "iframe src=video_url title=\"Intro video\"\n"),
  "AnchorHref" => Example.new("a Read more\n", "a href=post_path(post) Read more\n"),
  "NestedLinks" => Example.new("a href=\"/a\"\n  a href=\"/b\" B\n", "a href=\"/a\" A\na href=\"/b\" B\n"),
  "PositiveTabindex" => Example.new("button tabindex=\"3\" type=\"button\" Save\n", "button tabindex=\"0\" type=\"button\" Save\n"),
  "BooleanAttributeValue" => Example.new("input disabled=\"disabled\"\n", "input disabled=true\n"),
  "AriaRole" => Example.new("div role=\"buton\"\n", "div role=\"button\"\n"),
  "AriaAttribute" => Example.new("button aria-lable=\"Close\" type=\"button\"\n", "button aria-label=\"Close\" type=\"button\"\n"),
  "ButtonType" => Example.new("button Save\n", "button type=\"submit\" Save\n")
}.freeze

RULES_BY_GROUP = {
  "Layout — fixed by <code>slimx fmt</code>" =>
    %w[Indentation Tab TrailingWhitespace EmptyLines TrailingBlankLines ControlStatementSpacing RedundantDiv],
  "Template hygiene — from slim-lint" =>
    %w[LineLength CommentControlStatement EmptyControlStatement ConsecutiveControlStatements TagCase Zwsp],
  "Ruby in templates — from haml-lint and erb_lint" =>
    %w[UnnecessaryInterpolation UnnecessaryStringOutput DeprecatedClasses InlineStyles],
  "Rails conventions" => %w[InstanceVariables StrictLocals],
  "HTML and accessibility — from Herb and jsx-a11y" =>
    %w[DuplicateId ImageAlt IframeTitle AnchorHref NestedLinks PositiveTabindex BooleanAttributeValue AriaRole AriaAttribute ButtonType]
}.freeze

rule_names = SlimX::Linter::Rules.constants.map(&:name) - ["Rule"]
undocumented = rule_names - EXAMPLE_BY_RULE.keys
abort "Rules without an example: #{undocumented.join(", ")}" if undocumented.any?
ungrouped = EXAMPLE_BY_RULE.keys - RULES_BY_GROUP.values.flatten
abort "Rules without a group: #{ungrouped.join(", ")}" if ungrouped.any?

off_by_default = rule_names.reject { SlimX::Linter::Rules.const_get(_1)::DEFAULTS[:enabled] }
linter = SlimX::Linter.new(
  off_by_default.to_h { [_1, {"enabled" => true}] }.merge("DeprecatedClasses" => {"classes" => {"text-muted" => "text-body-secondary"}})
)
message_by_rule = EXAMPLE_BY_RULE.to_h do |rule, example|
  flagged = linter.call(example.path, example.flagged).find { _1.rule == rule }
  abort "#{rule}: the flagged example passes" unless flagged
  clean_offenses = linter.call(example.path, example.clean)
  abort "#{rule}: the clean example is flagged: #{clean_offenses.map(&:message).join(", ")}" if clean_offenses.any?

  [rule, flagged.message]
end

def escape(text) = CGI.escapeHTML(text)

def visible_source(rule, source)
  source = source.gsub(/ +$/) { "·" * _1.size } if rule == "TrailingWhitespace"
  source.gsub("\t", "→   ").gsub("​", "\\u200B")
end

rules_html = RULES_BY_GROUP.map do |title, rules|
  items = rules.map do |rule|
    example = EXAMPLE_BY_RULE.fetch(rule)
    default = off_by_default.include?(rule) ? %(<span class="rule-default off">off by default</span>) : ""
    message = escape(message_by_rule.fetch(rule)).gsub(/`([^`]+)`/) { "<code>#{$1}</code>" }
    <<~HTML
      <details class="rule">
        <summary><span class="rule-name">#{rule}</span>#{default}<span class="rule-message">#{message}</span></summary>
        <div class="rule-examples">
          <div><p class="example-label">Flagged</p><pre><code>#{escape(visible_source(rule, example.flagged))}</code></pre></div>
          <div><p class="example-label">Clean</p><pre><code>#{escape(example.clean)}</code></pre></div>
        </div>
      </details>
    HTML
  end
  %(<section class="rule-group"><h3>#{title}</h3>\n#{items.join}</section>\n)
end.join

page = File.read(PAGE_PATH)
abort "No <!-- linter-rules --> block in #{PAGE_PATH}" unless page.match?(RULES_BLOCK)
abort "No rule-count span in #{PAGE_PATH}" unless page.match?(RULE_COUNT)
page = page.sub(RULES_BLOCK) { "#{$1}#{rules_html}#{$2}" }.sub(RULE_COUNT) { "#{$1}#{EXAMPLE_BY_RULE.size}#{$2}" }
File.write(PAGE_PATH, page)
puts "#{EXAMPLE_BY_RULE.size} rules written to #{PAGE_PATH}"
