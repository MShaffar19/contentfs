# frozen_string_literal: true

require "pathname"

require_relative "content"
require_relative "prefix"
require_relative "slug"

module ContentFS
  # Structured content database, loaded from the filesystem.
  #
  class Database
    class << self
      def load(path)
        new(path: path)
      end
    end

    METADATA_FILE = "_metadata.yml"

    attr_reader :prefix, :slug

    def initialize(path:)
      path = Pathname.new(path)
      name = path.basename(path.extname)
      prefix, remainder = Prefix.build(name)
      @prefix = prefix
      @slug = Slug.build(remainder)
      @children = {}
      @nested = {}

      metadata_path = path.join(METADATA_FILE)

      metadata = if metadata_path.exist?
        YAML.safe_load(metadata_path.read).to_h
      else
        {}
      end

      Pathname.new(path).glob("*") do |path|
        next if path.basename.to_s.start_with?("_")

        if path.directory?
          database = Database.load(path)
          @nested[database.slug] = database
        else
          content = Content.load(path, metadata: metadata)

          if content.slug == :content
            @content = content
          else
            @children[content.slug] = content
          end
        end
      end
    end

    def content
      return to_enum(:content) unless block_given?

      @children.each_value do |value|
        yield value
      end
    end

    def nested
      return to_enum(:nested) unless block_given?

      @nested.each_value do |value|
        yield value
      end
    end

    def filter(**filters)
      return to_enum(:filter, **filters) unless block_given?

      filters = filters.each_with_object({}) { |(key, value), hash|
        hash[key.to_s] = value
      }

      @children.each_value.select { |content|
        yield content if content.metadata.all? { |key, value|
          filters[key] == value
        }
      }
    end

    def find(name, *nested)
      if @children.key?(name)
        @children[name]
      elsif @nested.key?(name)
        nested.inject(@nested[name]) { |database, next_nested|
          database.find(next_nested.to_sym)
        }
      end
    end

    def to_s
      @content&.to_s.to_s
    end

    def render
      @content&.render
    end

    def method_missing(name, *nested, **)
      find(name, *nested) || super
    end

    def respond_to_missing?(name, *)
      @children.key?(name) || super
    end
  end
end
