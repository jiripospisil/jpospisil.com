xml.instruct!
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  xml.url do
    xml.loc "http://jpospisil.com"
    xml.changefreq "daily"
    xml.priority "1.0"
  end

  sitemap.resources.select { |page| page.path =~ /^[0-9]{4}-[0-9]{2}/ }.each do |page|
    xml.url do
      xml.loc "http://jpospisil.com#{page.url}"
      xml.lastmod page.metadata[:page]["date"].split(" ").first
      xml.changefreq "weekly"
      xml.priority "0.9"
    end
  end
end
