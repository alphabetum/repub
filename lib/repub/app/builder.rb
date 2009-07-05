require 'fileutils'
require 'tmpdir'
require 'repub/epub'

module Repub
  class App
    module Builder

      class BuilderException < RuntimeError; end
      
      def build(parser)
        Builder.new(options).build(parser)
      end
  
      class Builder
        include Epub, Logger
        
        attr_reader :output_path
        attr_reader :document_path
        
        def initialize(options)
          @options = options
        end
        
        def build(parser)
          @parser = parser

          # Initialize content.opf
          @content = Content.new(@parser.uid)
          # Default title is the parsed one
          @content.metadata.title = @parser.title
          # Override metadata values specified in options
          if @options[:metadata]
            @content.metadata.members.each do |m|
              m = m.to_sym
              next if m == :identifier   # do not allow to override uid
              if @options[:metadata][m]
                @content.metadata[m] = @options[:metadata][m]
                log.debug "-- Setting metadata #{m} to \"#{@content.metadata[m]}\""
              end
            end
          end
          
          # Initialize toc.ncx
          @toc = Toc.new(@parser.uid)
          # TOC title is the same as in content.opf
          @toc.title = @content.metadata.title

          # Setup output filename and path
          @output_path = File.expand_path(@options[:output_path].if_blank('.'))
          if File.exist?(@output_path) && File.directory?(@output_path)
            @output_path = File.join(@output_path, @content.metadata.title.gsub(/\s/, '_'))
          end
          @output_path = @output_path +  '.epub'
          log.debug "-- Setting output path to #{@output_path}"
          
          # Build EPUB
          tmpdir = Dir.mktmpdir(App::name)
          begin
            FileUtils.chdir(tmpdir) do
              copy_and_process_assets
              write_meta_inf
              write_mime_type
              write_content
              write_toc
              write_epub
            end
          ensure
            # Keep tmp folder if we're going open processed doc in browser
            FileUtils.remove_entry_secure(tmpdir) unless @options[:browser]
          end
          self
        end
        
        private
        
        MetaInf = 'META-INF'
        
        def copy_and_process_assets
          # Copy html
          @parser.cache.assets[:documents].each do |doc|
            log.debug "-- Processing document #{doc}"
            # Copy asset from cache
            FileUtils.cp(File.join(@parser.cache.path, doc), '.')
            # Do post-processing
            postprocess_file(doc)
            postprocess_doc(doc)
            @content.add_item(doc)
            @document_path = File.expand_path(doc)
          end

          # Copy css
          if @options[:css].nil? || @options[:css].empty?
            # No custom css, copy one from assets
            @parser.cache.assets[:stylesheets].each do |css|
              log.debug "-- Copying stylesheet #{css}"
              FileUtils.cp(File.join(@parser.cache.path, css), '.')
              @content.add_item(css)
            end
          elsif @options[:css] != '-'
            # Copy custom css
            log.debug "-- Using custom stylesheet #{@options[:css]}"
            FileUtils.cp(@options[:css], '.')
            @content.add_item(File.basename(@options[:css]))
          end

          # Copy images
          @parser.cache.assets[:images].each do |image|
            log.debug "-- Copying image #{image}"
            FileUtils.cp(File.join(@parser.cache.path, image), '.')
            @content.add_item(image)
          end

          # Copy external custom files (-a option)
          @options[:add].each do |file|
            log.debug "-- Copying external file #{file}"
            FileUtils.cp(file, '.')
            @content.add_item(file)
          end if @options[:add]
        end
        
        def postprocess_file(asset)
          source = IO.read(asset)

          # Do rx substitutions
          @options[:rx].each do |rx|
            rx.strip!
            delimiter = rx[0, 1]
            rx = rx.gsub(/\\#{delimiter}/, "\n")
            ra = rx.split(/#{delimiter}/).reject {|e| e.empty? }.each {|e| e.gsub!(/\n/, "#{delimiter}")}
            raise ParserException, "Invalid regular expression" if ra.empty? || ra[0].nil? || ra.size > 2
            pattern = ra[0]
            replacement = ra[1] || ''
            log.info "Replacing pattern /#{pattern.gsub(/#{delimiter}/, "\\#{delimiter}")}/ with \"#{replacement}\""
            source.gsub!(Regexp.new(pattern), replacement)
          end if @options[:rx]

          # Add doctype if missing
          if source !~ /\s*<!DOCTYPE/
            log.debug "-- Adding missing doctype"
            source = "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">\n" + source
          end

          # Save processed file
          File.open(asset, 'w') do |f|
            f.write(source)
          end
        end
        
        def postprocess_doc(asset)
          doc = Nokogiri::HTML.parse(IO.read(asset), nil, 'UTF-8')

          # Set Content-Type charset to UTF-8
          doc.xpath('//head/meta[@http-equiv="Content-Type"]').each do |el|
            el['content'] = 'text/html; charset=utf-8'
          end

          # Process styles
          if @options[:css] && !@options[:css].empty?
            # Remove all stylesheet links
            doc.xpath('//head/link[@rel="stylesheet"]').remove
            if @options[:css] == '-'
              # Also remove all inline styles
              doc.xpath('//head/style').remove
              log.debug "-- Removing all stylesheet links and style elements"
            else
              # Add custom stylesheet link
              link = Nokogiri::XML::Node.new('link', doc)
              link['rel'] = 'stylesheet'
              link['type'] = 'text/css'
              link['href'] = File.basename(@options[:css])
              # Add as the last child so it has precedence over (possible) inline styles before
              doc.at('//head').add_child(link)
              log.debug "-- Replacing CSS refs with #{link['href']}"
            end
          end

          # Insert elements after/before selector
          @options[:after].each do |e|
            selector = e.keys.first
            fragment = e[selector]
            element = doc.xpath(selector).first
            if element
              element.add_next_sibling(fragment)
              log.info "Inserting fragment \"#{fragment.to_html}\" after \"#{selector}\""
            end
          end if @options[:after]
          @options[:before].each do |e|
            selector = e.keys.first
            fragment = e[selector]
            element = doc.xpath(selector).first
            if element
              element.add_previous_sibling(fragment)
              log.info "Inserting fragment \"#{fragment}\" before \"#{selector}\""
            end
          end if @options[:before]

          # Remove elements
          @options[:remove].each do |selector|
            log.info "Removing elements \"#{selector}\""
            doc.search(selector).remove
          end if @options[:remove]

          # Save processed doc
          File.open(asset, 'w') do |f|
            if @options[:fixup]
              # HACK: Nokogiri seems to ignore the fact that xmlns and other attrs aleady present
              # in html node and adds them anyway. Just remove them here to avoid duplicates.
              doc.root.attributes.each {|name, value| doc.root.remove_attribute(name) }
              doc.write_xhtml_to(f, :encoding => 'UTF-8')
            else
              doc.write_html_to(f, :encoding => 'UTF-8')
            end
          end
        end
        
        def write_meta_inf
          FileUtils.mkdir_p(MetaInf)
          FileUtils.chdir(MetaInf) do
            Epub::Container.new.save
          end
        end
        
        def write_mime_type
          File.open('mimetype', 'w') do |f|
            f << 'application/epub+zip'
          end
        end
    
        def write_content
          @content.save
        end
        
        def write_toc
          add_nav_points(@toc.nav_map, @parser.toc)
          @toc.save
        end
        
        def add_nav_points(nav_collection, toc)
          toc.each do |t|
            nav_point = nav_collection.add_nav_point(t.title, t.src)
            add_nav_points(nav_point, t.subitems) if t.subitems
          end
        end
        
        def write_epub
          %x(zip -X9 \"#{@output_path}\" mimetype)
          %x(zip -Xr9D \"#{@output_path}\" * -xi mimetype)
        end
      end

    end
  end
end
