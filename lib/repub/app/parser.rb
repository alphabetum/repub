require 'rubygems'
require 'hpricot'

module Repub
  class App
    module Parser
  
      class ParserException < RuntimeError; end
      
      def parse(cache)
        Parser.new(options).parse(cache)
      end
  
      # Default hpricot selectors
      #
      Selectors = {
        :title        => '//h1',
        :toc          => '//div.toc/ul',
        :toc_item     => '/li',
        :toc_section  => '/ul'
      }
      
      class Parser
        include Logger
        
        attr_reader :cache
        attr_reader :uid
        attr_reader :title
        attr_reader :title_html
        attr_reader :toc
        
        def initialize(options)
          @selectors = options[:selectors] || Selectors
          @fixup = options[:fixup]
        end
        
        def parse(cache)
          raise ParserException, "No HTML document found" if
            cache.assets[:documents].empty?
          raise ParserException, "More than one HTML document found, this is not supported (yet)" if
            cache.assets[:documents].size > 1
          
          @cache = cache
          @asset = @cache.assets[:documents][0]
          log.debug "-- Parsing #{@asset}"
          @doc = Hpricot(open(File.join(@cache.path, @asset)), @fixup)
          
          @uid = @cache.name
          parse_title
          parse_title_html
          parse_toc
          
          self
        end
        
        private
        
        UNTITLED = 'Untitled'
        
        def parse_title
          log.debug "-- Looking for title with #{@selectors[:title]}"
          el = @doc.at(@selectors[:title])
          if el
            if el.children.empty?
              title_text = el.inner_text
            else
              title_text =  el.children.map{|c| c.inner_text }.join(' ')
            end
            @title = title_text.gsub(/[\r\n]/, '').gsub(/\s+/, ' ').strip
            log.info "Found title \"#{@title}\""
          else
            @title = UNTITLED
            log.warn "** Could not parse document title, using '#{@title}'"
          end
        end
        
        def parse_title_html
          log.debug "-- Looking for html title with #{@selectors[:title]}"
          el = @doc.at(@selectors[:title])
          @title_html = el ? el.inner_html.gsub(/[\r\n]/, '') : UNTITLED
        end
        
        class TocItem < Struct.new(
            :title,
            :uri,
            :fragment_id
          )
          
          def initialize(title, uri_with_fragment_id, subitems, asset)
            self.title = title
            self.uri, self.fragment_id = uri_with_fragment_id.split(/#/)
            self.uri = asset if self.uri.empty?
            @subitems = subitems || []
          end
    
          attr_reader :subitems
          
          def src
            "#{uri}##{fragment_id}"
          end
        end
        
        def parse_toc
          log.debug "-- Looking for TOC with #{@selectors[:toc]}"
          el = @doc.at(@selectors[:toc])
          if el
            @toc = parse_toc_section(el)
            log.info "Found TOC with #{@toc.size} top-level items"
          else
            @toc = []
            log.warn "** Could not parse document table of contents"
          end
        end
        
        def parse_toc_section(section)
          toc = []
          log.debug "-- Looking for TOC items with #{@selectors[:toc_item]}"
          section.search(@selectors[:toc_item]).each do |item|
            a = item.name == 'a' ? item : item.at('a')
            href = a[:href]
            next if !a || !href
            title = item.inner_text.gsub(/\s+/, ' ').strip
            log.debug "-- Found item: #{title}"
            subitems = nil
            # subsection inside the item element or subsection immediately after the item
            # TODO
            subsections = item.search(@selectors[:toc_section])
            if subsections.empty? && !item.following_siblings.empty?
              subsections << item.following_siblings.first.at(@selectors[:toc_section])
            end
            subsections.compact!
            #p "++ #{item.search(@selectors[:toc_section])}"
            #p "== #{subsections.size}" if subsections
            #p subsections.size if subsections
            subsections.each do |subsection|
              log.debug "-- Found section with #{@selectors[:toc_section]} >>>"
              subitems = parse_toc_section(subsection)
              log.debug '-- <<<'
            end if subsections
            toc << TocItem.new(title, href, subitems, @asset)
          end
          toc
        end
      end

    end
  end    
end
