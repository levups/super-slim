# frozen_string_literal: true

# What golden templates can call. Values cover what breaks engines: markup to escape, nil, false, true, numbers,
# symbols, nested arrays, hashes for splats and data attributes, blocks, and strings already marked safe.
module GoldenScope
  Post = Struct.new(:id, :title, :url, :comments, :featured, :draft, :tags)

  def title = "Posts & comments"
  def markup = %(<b class="x">&'"</b>)
  def nothing = nil
  def yes = true
  def no = false
  def number = 42
  def decimal = 3.5
  def symbol = :primary
  def empty = ""
  def blank = "  "
  def unicode = "Café · naïve – 日本 🌍"
  def url = "/search?q=a&b=<c>"
  def classes = ["a", nil, ["b", ""], :c, false]
  def attributes = {:title => "<t>", "data-x" => 1, :disabled => true, :hidden => false, :id => nil}
  def data = {user_id: 1, nested: {deep: "<v>"}, flag: true, off: false, none: nil, list: [1, 2]}
  def aria = {label: "Close", hidden: true}
  def tag_name = "section"
  def items = %w[one two three]
  def wrap = "[#{yield}]"
  def safe_markup = SafeString.new("<i>safe</i>")

  def posts
    [
      Post.new(id: 1, title: "Hello <World>", url: "/posts/1", comments: "1,299", featured: true, draft: false, tags: %w[new popular]),
      Post.new(id: 2, title: "Tips & tricks", url: "/posts/2", comments: "499", featured: false, draft: true, tags: [])
    ]
  end

  # A string Rails would not escape again, for engines that honour html_safe?.
  class SafeString < String
    def html_safe? = true
    def to_s = self
  end
end
