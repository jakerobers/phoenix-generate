require "phoenix/generate/version"
require "recursive-open-struct"
require "json"
require "erb"
require "fileutils"


module Phoenix
  module Generate

    class ERBContext
      def initialize(schema)
        (class << self; self; end).class_eval do
          schema.each_pair do |key, value|
            if value.is_a?(Hash)
              value = RecursiveOpenStruct.new(value, recurse_over_arrays: true)
            end
            if value.is_a?(Array)
              value = value.map {|v| RecursiveOpenStruct.new(v, recurse_over_arrays: true)}
            end
            define_method key.to_sym do
              value
            end
          end
        end
      end

      def model_for_type(type)
        models.select do |model|
          model.type == type
        end.first
      end

      def bind
        binding
      end
    end

    class ModelContext < ERBContext
      attr_reader :model
      def initialize(schema, model)
        model.attributes ||= []
        model.relationships ||= []
        @model = model
        super(schema)
      end
    end

    def self.generate(target_directory)
      FileUtils.mkdir_p(target_directory)
      begin
        json = JSON.parse(STDIN.read)
        schema = ERBContext.new(json)
        Dir["./templates/api/**/*"].each do |file|
          full = File.join(Dir.pwd, file)
          fname = file[16..-1]
          matches = fname.match(/\$(.+?)\$/)
          if !matches.nil? && fname.match(/\*(.+)/).nil?
            fname = fname.sub!("$#{matches[1]}$", schema.send(matches[1].to_sym))
          end
          if(File.directory?(full))
            FileUtils.mkdir_p(File.join(target_directory, fname))
          else
            unless file.match(/\.erb/).nil?
              if /\*.+?\$.+?\$/ =~ file
                matches = file.match(/\*(.+?)\$(.+?)\$/)
                tfname = fname
                schema.send(matches[1].to_sym).each do |item|
                  fname = tfname[0..-5]
                  fname = fname.sub!("*#{matches[1]}", "")
                  fname = fname.sub!("$#{matches[2]}$", item.send(matches[2].to_sym))
                  f = File.new(File.join(target_directory, fname), "w")
                  f.write ERB.new(File.read(file), nil, "-").result(ModelContext.new(json, item).bind)
                  f.close
                end
              else
                fname = fname[0..-5]
                f = File.new(File.join(target_directory, fname), "w")
                f.write ERB.new(File.read(file), nil, "<>").result(schema.bind)
                f.close
              end
            else
              FileUtils.cp(File.join(Dir.pwd, file), File.join(target_directory, file[16..-1]))
            end
          end
        end
      rescue => e
        puts "Invalid JSON"
        raise e
      end
    end
  end
end
