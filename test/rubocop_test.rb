# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"

class RuboCopTest < Minitest::Test
  TEMPLATE = <<~'SLIM'
    - if foo == nil
      p class=bar( 1 ) title="x #{baz.map{|i| i}}" = qux "a",
        'b'
    - items.each do |item|
      == item.name.to_s()
    - case x
    - when 'a', "b"
      | Hi #{{raw "y"}}
    ruby:
      w = [1,2]
    span> data-a="1" = puts "out"
  SLIM

  CORRECTED = <<~'SLIM'
    - if foo.nil?
      p class=bar(1) title="x #{baz.map { |i| i }}" = qux 'a',
        'b'
    - items.each do |item|
      == item.name.to_s
    - case x
    - when 'a', 'b'
      | Hi #{{raw 'y'}}
    ruby:
      w = [1, 2]
    span> data-a="1" = puts 'out'
  SLIM

  def test_offenses_point_at_the_template
    assert_equal ["1:10 Style/NilComparison", "2:15 Layout/SpaceInsideParens", "2:17 Layout/SpaceInsideParens",
      "2:38 Layout/SpaceBeforeBlockBraces", "2:38 Layout/SpaceInsideBlockBraces", "2:44 Layout/SpaceInsideBlockBraces",
      "2:54 Style/StringLiterals", "5:20 Style/MethodCallWithoutArgsParentheses", "7:13 Style/StringLiterals",
      "8:15 Style/StringLiterals", "10:9 Layout/SpaceAfterComma", "11:25 Style/StringLiterals"],
      rubocop("--format", "emacs").scan(/:(\d+:\d+): C: \[Correctable\] (\S+):/).map { _1.join(" ") }
  end

  def test_autocorrection_writes_into_the_template
    rubocop("--autocorrect-all")

    assert_equal CORRECTED, File.read(File.join(@directory, "page.html.slim"))
  end

  def test_a_template_super_slim_cannot_parse_has_no_offense
    assert_includes rubocop("--format", "simple", template: "p(\n"), "no offenses detected"
  end

  def teardown
    FileUtils.rm_rf(@directory)
  end

  private

  # A process of its own: RuboCop memoizes the working directory and the project root.
  def rubocop(*options, template: TEMPLATE)
    @directory = Dir.mktmpdir
    File.write(File.join(@directory, "page.html.slim"), template)
    File.write(File.join(@directory, ".rubocop.yml"), <<~YAML)
      plugins:
        - super-slim
      AllCops:
        NewCops: disable
        SuggestExtensions: false
    YAML
    IO.popen([Gem.ruby, Gem.bin_path("rubocop", "rubocop"), "--cache", "false", *options, "page.html.slim"], chdir: @directory, &:read)
  end
end
