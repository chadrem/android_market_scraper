require 'rubygems'
require 'net/http'
require 'net/https'
require 'nokogiri'
require 'csv'
require 'ruby-debug' rescue nil

module AndroidMarketScraper
  class AppInfo
    ATTRIBUTES = [:market_rank, :title, :developer, :price_usd, :market_id, :market_url, :stars,
                  :updated, :app_version, :minimum_android_version, :category, :installs,
                  :installs_min, :installs_max, :size]

    def initialize(options={})
      ATTRIBUTES.each do |attrib|
        instance_variable_set("@#{attrib}", options[attrib])
      end
    end

    def method_missing(symbol)
      if ATTRIBUTES.include?(symbol)
        return instance_variable_get("@#{symbol}")
      else
        raise NoMethodError
      end
    end
  end

  class AppInfoSet
    def initialize(app_infos=[])
      @app_infos = app_infos
    end

    def <<(app_info)
      @app_infos << app_info

      return self
    end

    def output_report
      CSV::Writer.generate(STDOUT) do |csv|
        csv << AppInfo::ATTRIBUTES
        @app_infos.each do |app|
          csv << AppInfo::ATTRIBUTES.map{ |attrib| app.send(attrib).to_s }
        end
      end
    end
  end

  class Scraper
    def initialize
      @items_per_page = 24
      @default_max_pages = 35
    end

    def fetch(url)
      url = URI.parse(url)
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true if url.port == 443
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE if url.port == 443
      path = url.path + "?" + url.query
      res, data = http.get(path)

      return data
    end

    def scrape(options={})
      max_pages = options[:max_pages] || @default_max_pages
      category = options[:category] || 'GAME'
      purchase_type = options[:purchase_type] || 'free'

      market_rank = 0
      app_info_set = AppInfoSet.new

      # Loop through every rankings page.
      (0..max_pages).each do |page|
        start_offset = 24 * page

        base_url = "https://market.android.com/details"
        url_params = "?id=apps_topselling_#{purchase_type}&cat=#{category}&start=#{start_offset}&num=24"
        doc = Nokogiri::HTML(fetch(base_url + url_params))

        # Loop through every app on a specific rankings page.
        doc.css('.snippet').each do |snippet_node|
          details_node = snippet_node.css('.details')

          # App info from the rankings page.

          title     = details_node.css('.title').first.attributes['title'].to_s
          price_usd = details_node.css('.buy-button-price').children.first.text.gsub(' Buy', '')
          developer = details_node.css('.attribution').children.first.text
          market_id = details_node.css('.title').first.attributes['href'].to_s.gsub('/details?id=', '')

          stars_text = snippet_node.css('.ratings').first.attributes['title'].value
          stars = /Rating: (.+) stars .*/.match(stars_text)[1]

          market_url = "https://market.android.com/details?id=#{market_id}"

          if price_usd == 'Install'
            price_usd = '$0.00'
          end

          $stderr.puts "Processing app: #{title}"

          # App info from the application specific page.

          app_specific_doc = Nokogiri::HTML(fetch(market_url))
          about_node = app_specific_doc.css('.doc-metadata').first.elements[2]

          updated                 = about_node.elements[3].text
          app_version             = about_node.elements[5].text
          minimum_android_version = about_node.elements[7].text
          app_category            = about_node.elements[9].text
          installs                = about_node.elements[11].text
          size                    = about_node.elements[13].text

          minimum_android_version.gsub!(' and up', '')

          installs_min = installs.split(' - ')[0]
          installs_max = installs.split(' - ')[1]

          # Build an AppInfo object and append it to the app info set.

          app_info = AppInfo.new(:title => title, :price_usd => price_usd, :developer => developer,
                                 :stars => stars, :market_id => market_id, :market_url => market_url,
                                 :market_rank => (market_rank+=1), :updated => updated,
                                 :app_version => app_version, :minimum_android_version => minimum_android_version,
                                 :category => app_category, :installs => installs,
                                 :installs_min => installs_min, :installs_max => installs_max, :size => size)

          app_info_set << app_info
        end
      end

      return app_info_set
    end
  end
end

AndroidMarketScraper::Scraper.new.scrape(
  :max_pages => 01,         # Seems to go up to about 35.  Check the website.
  :category => 'GAME',      # Many categories based on URL (example: https://market.android.com/apps/GAME/)
  :purchase_type => 'free'  # paid or free.
).output_report
