require "phoenix/generate/version"
require "recursive-open-struct"
require "json"
require "erb"
require "fileutils"


module Phoenix
  module Generate

    class Node
      attr_accessor :value
      attr_accessor :parents
      def initialize(value, parents)
        @value = value
        @parents = parents
      end

    end

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

        json["models"] = json["models"].sort do |a,b|
          ret = 0
          ret = -1 if a["relationships"].nil?
          ret = 1 if b["relationships"].nil?
          if ret === 0
            if a["relationships"].map{|rel| rel["type"]}.include?(b["type"]) && ["many_to_one"].include?(a["relationships"].find {|c| c["type"] == b["type"]}["rel"])
              ret = 1
            elsif b["relationships"].map{|rel| rel["type"]}.include?(a["type"]) && ["many_to_one"].include?(b["relationships"].find {|c| c["type"] == a["type"]}["rel"])
              ret = -1
            else
              ret = 0
            end
          end
          ret
        end.each_with_index.map{|x, i|
          x["index"] = Time.now.strftime("%Y%m%d%H%M%S%L") + i.to_s
          x
        }

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
                repeats = file.match(/\*(.+?)\$/)
                replaces = file.scan(/\$(.+?)\$/)
                tfname = fname
                schema.send(repeats[1].to_sym).each do |item|
                  fname = tfname[0..-5]
                  fname = fname.sub!("*#{repeats[1]}", "")
                  replaces.flatten.each do |replace|
                    fname = fname.sub!("$#{replace}$", item.send(replace.to_sym).to_s)
                  end
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
