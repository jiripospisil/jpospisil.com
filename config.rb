Time.zone = "UTC"

activate :blog do |blog|
  blog.summary_length    = nil
  blog.tag_template      = "tag.html"
  blog.calendar_template = "calendar.html"
  blog.paginate          = true
  blog.per_page          = 10
  blog.page_link         = "page/:num"
  blog.layout            = "post"
end

activate :syntax

set :markdown_engine, :redcarpet
set :markdown, fenced_code_blocks: true, smartypants: true

page "/feed.xml", layout: false
page "/sitemap.xml", layout: false

require "slim"

set :css_dir, "stylesheets"
set :js_dir, "javascripts"
set :images_dir, "images"

configure :development do
  set :debug_assets, true
end

configure :build do
  activate :minify_css
  activate :minify_javascript
  activate :minify_html, remove_http_protocol: false, remove_https_protocol: false
  activate :gzip
  activate :asset_hash
end
