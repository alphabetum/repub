require 'rubygems'
require 'builder'

module Repub
  module Epub
  
  # Open Packaging Format (OPF) 2.0 wrapper
  # (see http://www.idpf.org/2007/opf/OPF_2.0_final_spec.html)
  #
  class OPF
    
    def initialize(uid)
      @metadata = Metadata.new('Untitled', 'en', uid, Date.today.to_s)
      @manifest_items = []
      @spine_items = []
      @manifest_items << PackageItem.new('ncx', 'toc.ncx')
    end
    
    class Metadata < Struct.new(
        :title,
        :language,
        :identifier,
        :date,
        :subject,
        :description,
        :relation,
        :creator,
        :publisher,
        :rights
      )
    end
    
    attr_reader :metadata

    def add_item(href, id = nil)
      item = PackageItem.new(id || "item_#{@manifest_items.size}", href)
      @manifest_items << item
      @spine_items << item if item.document?
    end
    
    def to_xml
      out = ''
      builder = Builder::XmlMarkup.new(:target => out)
      builder.instruct!
      builder.package :xmlns => "http://www.idpf.org/2007/opf",
          'unique-identifier' => "dcidid",
          'version' => "2.0" do
        metadata_to_xml(builder)
        manifest_to_xml(@manifest_items, builder)
        spine_to_xml(@spine_items, builder)
      end
      out
    end
    
    def save(path = 'package.opf')
      File.open(path, 'w') do |f|
        f << to_xml
      end
    end
    
    private

    def metadata_to_xml(builder)
      builder.metadata 'xmlns:dc' => "http://purl.org/dc/elements/1.1/",
        'xmlns:dcterms' => "http://purl.org/dc/terms/",
        'xmlns:xsi' => "http://www.w3.org/2001/XMLSchema-instance",
        'xmlns:opf' => "http://www.idpf.org/2007/opf" do
          # Required elements
          builder.dc :title do
            builder << @metadata.title
          end
          builder.dc :language, 'xsi:type' => "dcterms:RFC3066" do
            builder << @metadata.language
          end
          builder.dc :identifier, :id => 'dcidid', 'opf:scheme' => 'URI' do
            builder << @metadata.identifier
          end
          # Optional elements
          builder.dc :subject do
            builder << @metadata.subject
          end if @metadata.subject
          builder.dc :description do
            builder << @metadata.description
          end if @metadata.description
          builder.dc :relation do
            builder << @metadata.relation
          end if @metadata.relation
          builder.dc :creator do                  # TODO: roles
            builder << @metadata.creator
          end if @metadata.creator
          builder.dc :publisher do
            builder << @metadata.publisher
          end if @metadata.publisher
          builder.dc :date do
            builder << @metadata.date.to_s
          end if @metadata.date
          builder.dc :rights do
            builder << @metadata.rights
          end if @metadata.rights
      end
    end
    
    class PackageItem < Struct.new(
        :id,
        :href,
        :media_type
      )

      def initialize(id, href)
        super(id, href)
        self.media_type = case href.strip.downcase
          when /.*\.html?$/
            'application/xhtml+xml'
          when /.*\.css$/
            'text/css'
          when /.*\.(jpeg|jpg)$/
            'image/jpeg'
          when /.*\.png$/
            'image/png'
          when /.*\.gif$/
            'image/gif'
          when /.*\.svg$/
            'image/svg+xml'
          when /.*\.ncx$/
            'application/x-dtbncx+xml'
          else
            raise 'Unknown media type'
        end
      end

      def document?
        self.media_type == 'application/xhtml+xml'
      end
    end
    
    def manifest_to_xml(manifest_items, builder)
      builder.manifest do
        manifest_items.each do |i|
          builder.item :id => i[:id], :href => i[:href], 'media-type' => i[:media_type]
        end
      end
    end
    
    def spine_to_xml(spine_items, builder)
      builder.spine do
        spine_items.each do |i|
          builder.itemref :idref => i[:id]
        end
      end
    end
  
  end
  
  end
end
