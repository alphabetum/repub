require 'fileutils'
require 'digest/sha1'
require 'uri'
require 'iconv'
require 'rubygems'
require 'UniversalDetector'

module Repub
  class App
    module Fetcher
    
      class FetcherException < RuntimeError; end

      def fetch
        Helper.new(options[:helper]).fetch(options[:url])
      end
    
      AssetTypes = {
        :documents => %w[html htm],
        :stylesheets => %w[css],
        :images => %w[jpg jpeg png gif svg]
      }
  
      class Helper
        Downloaders = {
          :wget     => { :cmd => 'wget', :options => '-nv -E -H -k -p -nH -nd' },
          :httrack  => { :cmd => 'httrack', :options => '-gB -r2 +*.css +*.jpg -*.xml -*.html' }
        }
        
        def initialize(name)
          @downloader_path, @downloader_options = ENV['REPUB_HELPER'], ENV['REPUB_downloader_options']
          begin
            downloader = Downloaders[name.to_sym] rescue Downloaders[:wget]
            @downloader_path ||= which(downloader[:cmd])
            @downloader_options ||= downloader[:options]
          rescue RuntimeError
            raise FetcherException, "unknown helper '#{name}'"
          end
        end
        
        def fetch(url)
          raise FetcherException, "empty URL" if url.nil? || url.empty?
          begin
            URI.parse(url)
          rescue
            raise FetcherException, "invalid URL: #{url}"
          end
          cmd = "#{@downloader_path} #{@downloader_options} #{url}"
          Cache.for_url(url) do |cache|
            unless system(cmd) && !cache.empty?
              raise FetcherException, "Fetch failed."
            end
          end
        end
        
        private
        
        def which(cmd)
          if !RUBY_PLATFORM.match('mswin')
            cmd = `/usr/bin/which #{cmd}`.strip
            raise FetcherException, "#{cmd}: helper not found." if cmd.empty?
          end
          cmd
        end
      end

      class Cache
        def self.root
          return File.join(App.data_path, 'cache')
        end
      
        def self.inventorize
          # TODO 
        end
      
        def self.cleanup
          Dir.chdir(self.root) { FileUtils.rm_r(Dir.glob('*')) }
        rescue
          # ignore exceptions
        end
      
        attr_reader :url
        attr_reader :name
        attr_reader :path
        attr_reader :assets
      
        def self.for_url(url, &block)
          self.new(url).for_url(&block)
        end
      
        def for_url(&block)
          # if not yet cached, download stuff
          unless File.exist?(@path)
            FileUtils.mkdir_p(@path) 
            begin
              Dir.chdir(@path) { yield self }
            rescue
              FileUtils.rm_r(@path)
              raise
            end
          end
          # do post-download tasks
          if File.exist?(@path)
            Dir.chdir(@path) do
              # enumerate assets
              @assets = {}
              AssetTypes.each_pair do |asset_type, file_types|
                @assets[asset_type] ||= []
                file_types.each do |file_type|
                  @assets[asset_type] << Dir.glob("*.#{file_type}")
                end
                @assets[asset_type].flatten!
              end
              # detect encoding and convert to utf-8 if needed
              @assets[:documents].each do |doc|
                s = IO.read(doc)
                encoding = UniversalDetector::chardet(s)['encoding']
                if encoding.downcase != 'utf-8'
                  s = Iconv.conv('utf-8', encoding, s)
                  File.open(doc, 'w') { |f| f.write(s) }
                end
              end
            end
          end
          self
        end
      
        def empty?
          Dir.glob(File.join(@path, '*')).empty?
        end
      
        private
      
        def initialize(url)
          @url = url
          @name = Digest::SHA1.hexdigest(@url)
          @path = File.join(Cache.root, @name)
        end
      end
      
    end
  end
end
