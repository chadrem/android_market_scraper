require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'csv'
require 'ruby-debug'

module AndroidMarketScraper
  class AppInfo
    ATTRIBUTES = [:market_rank, :title, :developer, :price_usd, :market_id, :market_url, :stars]

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

    def scrape(options={})
      max_pages = options[:max_pages] || @default_max_pages
      category = options[:category] || 'GAME'
      purchase_type = options[:purchase_type] || 'free'

      market_rank = 0
      app_info_set = AppInfoSet.new

      (0..max_pages).each do |page|
        start_offset = 24 * page

        base_url = "https://market.android.com/details"
        url_params = "?id=apps_topselling_#{purchase_type}&cat=#{category}&start=#{start_offset}&num=24"
        doc = Nokogiri::HTML(open(base_url + url_params))

        doc.css('.snippet').each do |snippet_node|
          details_node = snippet_node.css('.details')

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

          app_info_set << AppInfo.new(:title => title, :price_usd => price_usd, :developer => developer,
                                      :stars => stars, :market_id => market_id, :market_url => market_url,
                                      :market_rank => (market_rank+=1))
        end
      end

      return app_info_set
    end
  end
end

AndroidMarketScraper::Scraper.new.scrape(
  :max_pages => 02          # Seems to go up to about 35.  Check the website.
  :category => 'GAME',      # This can be many things based on the url (example: https://market.android.com/apps/GAME/)
  :purchase_type => 'paid'  # paid or free.
).output_report
