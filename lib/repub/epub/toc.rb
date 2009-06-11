module RePub
  
  require 'rubygems'
  require 'builder'
  require 'uuid'
  
  class Toc
    
    def initialize(uid)
      @head = Head.new(uid)
      @doc_title = DocTitle.new('Untitled')
      @nav_map = NavMap.new
    end

    def title
      @doc_title.text
    end
    
    def title=(text)
      @doc_title = DocTitle.new(text)
    end
    
    attr_reader :nav_map
    
    def to_xml
      out = ''
      builder = Builder::XmlMarkup.new(:target => out, :indent => 4)
      builder.instruct!
      builder.declare! :DOCTYPE, :ncx, :PUBLIC, "-//NISO//DTD ncx 2005-1//EN", "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd"
      builder.ncx :xmlns => "http://www.daisy.org/z3986/2005/ncx/", :version => "2005-1" do
        @nav_map.calc_depth_and_play_order
        @head.depth = @nav_map.depth
        @head.to_xml(builder)
        @doc_title.to_xml(builder)
        @nav_map.to_xml(builder)
      end
      out
    end
    
    def save(path = 'toc.ncx')
      File.open(path, 'w') do |f|
        f << to_xml
      end
    end
    
    class Head < Struct.new(
        :uid
      )
      
      attr_accessor :depth
      
      def to_xml(builder)
        builder.head do 
          builder.meta :name => "dtb:uid", :content => self.uid
          builder.meta :name => "dtb:depth", :content => @depth
          builder.meta :name => "dtb:totalPageCount", :content => 0
          builder.meta :name => "dtb:dtb:maxPageNumber", :content => 0
        end
      end
    end
    
    class DocTitle < Struct.new(
        :text
      )
      
      def to_xml(builder)
        builder.docTitle do 
          builder.text self.text
        end
      end
    end
    
    class NavMap
      class NavPoint < Struct.new(
          :title,
          :src
        )
        
        def initialize(title, src)
          super
          @@last_play_order = 0
          @play_order = 0
          @child_points = []
        end
        
        def add_nav_point(title, src)
          nav_point = NavPoint.new(title, src)
          @child_points << nav_point
          nav_point
        end
        
        def to_xml(builder)
          builder.navPoint :id => "navPoint-#{@play_order}", :playOrder => @play_order do
            builder.navLabel do
              builder.text self.title
            end
            builder.content :src => self.src
            @child_points.each { |child_point| child_point.to_xml(builder) }
          end
        end
        
        def calc_depth_and_play_order(nav_map, depth)
          nav_map.depth = depth
          @play_order = @@last_play_order += 1
          @child_points.each { |child_point| child_point.calc_depth_and_play_order(nav_map, depth + 1) }
        end
      end
      
      def initialize
        @nav_points = []
        @depth = 1
      end
      
      def add_nav_point(title, src)
        nav_point = NavPoint.new(title, src)
        @nav_points << nav_point
        nav_point
      end
    
      attr_reader :depth
      
      def depth=(value)
        @depth = value if value > @depth
      end
      
      def calc_depth_and_play_order
        @nav_points.each { |nav_point| nav_point.calc_depth_and_play_order(self, 1) }
      end
      
      def to_xml(builder)
        builder.navMap do
          @nav_points.each { |nav_point| nav_point.to_xml(builder) }
        end
      end
    end
  end
end

if __FILE__ == $0

  require "test/unit"
  require 'hpricot'

  class TestToc < Test::Unit::TestCase
    def test_toc_create
      x = RePub::Toc.new(UUID.new.generate)
      s = x.to_xml
      #puts s
      #doc = Hpricot(s)
    end
    
    def test_toc
      x = RePub::Toc.new(UUID.new.generate)
      p0 = x.nav_map.add_nav_point('Intro', 'intro.html')
      p1 = x.nav_map.add_nav_point('Chapter 1', 'chapter-1.html')
      p2 = x.nav_map.add_nav_point('Chapter 2', 'chapter-2.html')
      p21 = p2.add_nav_point('Chapter 2-1', 'chapter-2-1.html')
      pg = x.nav_map.add_nav_point('Glossary', 'glossary.html')
      p11 = p1.add_nav_point('Chapter 1-1', 'chapter-1-1.html')
      p12 = p1.add_nav_point('Chapter 1-2', 'chapter-1-2.html')
      s = x.to_xml
      puts s
      #doc = Hpricot(s)
    end
  end

end
