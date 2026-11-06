# frozen_string_literal: true

# Downloads the .slim files of every project in corpus/manifest.yml, at its pinned commit, into corpus/cache.
# Only the templates are fetched, never the repositories, and files already there are skipped. The cache is
# ignored by git: these projects keep their own licenses and are never committed here.
#   rake corpus:fetch
require "date"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "yaml"

CORPUS_DIRECTORY = File.expand_path("../corpus", __dir__)
CACHE_DIRECTORY = File.join(CORPUS_DIRECTORY, "cache")
CONNECTION_COUNT = 16
ATTEMPT_COUNT = 4

Download = Data.define(:repository, :sha, :path) do
  def destination = File.join(CACHE_DIRECTORY, repository.tr("/", "_"), path)
  def request_path = "/#{repository}/#{sha}/#{path.split("/").map { URI.encode_uri_component(_1) }.join("/")}"
end

# A pinned commit's list never changes: once listed, a project needs no API call, so a full cache works offline.
def slim_paths(repository, sha)
  project_directory = File.join(CACHE_DIRECTORY, repository.tr("/", "_"))
  listing_path = File.join(project_directory, ".slim_paths_#{sha}")
  return File.readlines(listing_path, chomp: true) if File.exist?(listing_path)

  # Templates fetched at another commit would be checked as if they were this one's, deleted ones included.
  FileUtils.rm_rf(project_directory)

  ATTEMPT_COUNT.times do |attempt|
    tree_json, status = Open3.capture2("gh", "api", "repos/#{repository}/git/trees/#{sha}?recursive=1")
    next sleep(2**attempt) unless status.success?

    paths = JSON.parse(tree_json).fetch("tree").filter_map { |entry| entry["path"] if entry["type"] == "blob" && entry["path"].end_with?(".slim") }
    FileUtils.mkdir_p(File.dirname(listing_path))
    File.write(listing_path, paths.map { "#{_1}\n" }.join)
    return paths
  end
  abort "Cannot list #{repository}@#{sha}: gh api failed #{ATTEMPT_COUNT} times"
end

# Authenticated requests are not throttled like anonymous ones: the token of the CI, or of gh on a laptop.
def authorization_header
  token = ENV["GH_TOKEN"] || ENV["GITHUB_TOKEN"] || Open3.capture2("gh", "auth", "token").then { |output, status| output.strip if status.success? }
  token.to_s.empty? ? {} : {"Authorization" => "token #{token}"}
end

def fetch(http, download, headers)
  ATTEMPT_COUNT.times do |attempt|
    response = http.get(download.request_path, headers)
    if response.is_a?(Net::HTTPSuccess)
      FileUtils.mkdir_p(File.dirname(download.destination))
      return File.write(download.destination, response.body.force_encoding(Encoding::UTF_8))
    end
    return warn("  #{download.repository}/#{download.path}: HTTP #{response.code}") unless %w[429 500 502 503 504].include?(response.code)

    sleep(2**attempt)
  end
  warn "  #{download.repository}/#{download.path}: gave up after #{ATTEMPT_COUNT} attempts"
end

manifest = YAML.load_file(File.join(CORPUS_DIRECTORY, "manifest.yml"), permitted_classes: [Date])
# corpus:check reads every directory of the cache: a project dropped from the manifest goes with it.
project_directories = manifest.map { File.join(CACHE_DIRECTORY, _1.fetch("repo").tr("/", "_")) }
(Dir.glob(File.join(CACHE_DIRECTORY, "*")) - project_directories).each { FileUtils.rm_rf(_1) }
downloads = manifest.map do |project|
  Thread.new do
    repository, sha = project.fetch("repo"), project.fetch("sha")
    all = slim_paths(repository, sha).map { Download.new(repository, sha, _1) }
    missing = all.reject { File.exist?(_1.destination) }
    puts "#{repository}: #{all.size} templates, #{missing.size} to fetch"
    missing
  end
end.flat_map(&:value)

exit if downloads.empty?

queue = Queue.new
downloads.each { queue << _1 }
queue.close
headers = authorization_header
Array.new([CONNECTION_COUNT, downloads.size].min) do
  Thread.new do
    Net::HTTP.start("raw.githubusercontent.com", 443, use_ssl: true) do |http|
      while (download = queue.pop)
        fetch(http, download, headers)
      end
    end
  end
end.each(&:join)
puts "#{downloads.size} templates fetched"
