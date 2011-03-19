require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'ruby-debug'

module AndroidMarketScraper
  class AppInfo
    @@app_attributes = [:developer, :price, :market_id, :market_rank, :stars, :title]

    def initialize(options={})
      @@app_attributes.each do |attrib|
        instance_variable_set("@#{attrib}", options[attrib])
      end
    end

    def method_missing(symbol)
      if @@app_attributes.include?(symbol)
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
      @app_infos.each do |app|
        puts "#{app.title}, #{app.market_rank}"
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

        doc.css('.details').each do |node|
          title = node.css('.title').first.attributes['title'].to_s

          app_info_set << AppInfo.new(:title => title, :market_rank => (market_rank+=1))
        end
      end

      return app_info_set
    end
  end
end

AndroidMarketScraper::Scraper.new.scrape(:max_pages => 5, :category => 'GAME', :purchase_type => 'paid').output_report
