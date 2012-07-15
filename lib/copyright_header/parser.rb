require 'fileutils'
require 'yaml'
require 'erb'
require 'ostruct'

module CopyrightHeader
  class FileNotFoundException < Exception; end

  class License
    @lines = []
    def initialize(options)
      @options = options
      @lines = load_template.split(/(\n)/)
    end

    def word_wrap(text, max_width = nil)
      max_width ||= @options[:word_wrap]
      text.gsub(/(.{1,#{max_width}})(\s|\Z)/, "\\1\n")
    end

    def load_template
      if File.exists?(@options[:license_file])
        template = ::ERB.new File.new(@options[:license_file]).read, 0, '%<'
        license = template.result(OpenStruct.new(@options).instance_eval { binding }) 
        license += "\n" if license !~ /\n$/s
        word_wrap(license)
      else
        raise FileNotFoundException.new("Unable to open #{file}")
      end
    end

    def format(comment_open = nil, comment_close = nil, comment_prefix = nil)
      comment_open ||= ''
      comment_close ||= ''
      comment_prefix ||= ''
      license = comment_open + @lines.map { |line| comment_prefix + line }.join() + comment_close
      license.gsub!(/\\n/, "\n")
      license
    end
  end

  class Header
    @file = nil
    @contents = nil
    @config = nil

    def initialize(file, config)
      @file = file
      @contents = File.read(@file)
      @config = config
    end

    def format(license)
      license.format(@config[:comment]['open'], @config[:comment]['close'], @config[:comment]['prefix'])
    end

    def add(license)
      if has_copyright?
        puts "SKIP #{@file}; detected exisiting license"
        return nil
      end

      copyright = self.format(license)
      if copyright.nil?
        puts "Copyright is nil"
        return nil
      end

      text = ""
      if @config.has_key?(:after) && @config[:after].instance_of?(Array)
        copyright_written = false
        lines = @contents.split(/\n/)
        head = lines.shift(10)
        while(head.size > 0)
          line = head.shift
          text += line + "\n"
          @config[:after].each do |regex|
            pattern = Regexp.new(regex)
            if pattern.match(line)
              text += copyright
              copyright_written = true
              break
            end
          end
        end
        if copyright_written
          text += lines.join("\n")
        else
          text = copyright + text + lines.join("\n")
        end
      else
        # Simply prepend text
        text = copyright + @contents
      end
      return text
    end

    def remove(license)
      if has_copyright?
        text = self.format(license)
        @contents.gsub!(/#{Regexp.escape(text)}/, '')
        @contents
      else
        puts "SKIP #{@file}; copyright not detected"
        return nil
      end
    end

    def has_copyright?(lines = 10)
      @contents.split(/\n/)[0..lines].select { |line| line =~ /[Cc]opyright|[Ll]icense/ }.length > 0
    end
  end

  class Syntax
    def initialize(config)
      @config = {}
      syntax = YAML.load_file(config)
      syntax.each_value do |format|
        format['ext'].each do |ext|
          @config[ext] = {
            :before => format['before'],
            :after => format['after'],
            :comment => format['comment']
          }
        end
      end
    end

    def ext(file)
      File.extname(file)
    end

    def supported?(file)
      @config.has_key? ext(file)
    end

    def header(file)
      Header.new(file, @config[ext(file)])
    end
  end

  class Parser
    attr_accessor :options
    @syntax = nil
    @license = nil
    def initialize(options = {})
      @options = options
    @exclude = [ /^LICENSE(|\.txt)$/i, /^holders(|\.txt)$/i, /^README/, /^\./]
      @license = License.new(:license_file => @options[:license_file],
                             :copyright_software => @options[:copyright_software],
                             :copyright_software_description => @options[:copyright_software_description],
                             :copyright_years => @options[:copyright_years],
                             :copyright_holders => @options[:copyright_holders],
                             :word_wrap => @options[:word_wrap])
      @syntax = Syntax.new(@options[:syntax])
    end

    def execute
      if @options.has_key?(:add_path)
        add(@options[:add_path])
      end

      if @options.has_key?(:remove_path)
        remove(@options[:remove_path])
      end
    end

    def transform(method, path)
      paths = []
      if File.file?(path)
        paths << path
      else
        paths << Dir.glob("#{path}/**/*")
      end

      puts paths.inspect

      paths.flatten!

      paths.each do |path|
        if File.file?(path)
          if @exclude.include? File.basename(path)
            puts "SKIP #{path}; excluded"
            next
          end

        if @syntax.supported?(path) 
          header = @syntax.header(path)
            contents = header.send(method, @license)
            if contents.nil?
              puts "SKIP #{path}; failed to generate license"
            else
              write(path, contents)
            end
          end
        else
          puts "SKIP #{path}; unsupported"
        end
      end
    end

    # Add copyright header recursively
    def add(dir)
      transform(:add, dir)
    end

    # Remove copyright header recursively
    def remove(dir)
      transform(:remove, dir)
    end

    def write(file, contents)
      puts "UPDATE #{file}"
      if @options[:dry_run] || @options[:output_dir].nil?
        puts contents
      else
        dir = "#{@options[:output_dir]}/#{File.dirname(file)}"
        FileUtils.mkpath dir unless File.directory?(dir)
        output_path = @options[:output_dir] + file
        f =File.new(output_path, 'w')
        f.write(contents)
        f.close
      end
    end
  end
end
