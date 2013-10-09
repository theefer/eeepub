# require 'zipruby'
require 'zip/zip'

module EeePub
  # Class to create OCF
  class OCF
    # Class for 'container.xml' of OCF
    class Container < ContainerItem
      attr_accessor :rootfiles

      # @param [String or Array or Hash]
      #
      # @example
      #   # with String
      #   EeePub::OCF::Container.new('container.opf')
      #
      # @example
      #   # with Array
      #   EeePub::OCF::Container.new(['container.opf', 'other.opf'])
      #
      # @example
      #   # with Hash
      #   EeePub::OCF::Container.new(
      #     :rootfiles => [
      #       {:full_path => 'container.opf', :media_type => 'application/oebps-package+xml'}
      #     ]
      #   )
      def initialize(arg)
        case arg
        when String
          set_values(
            :rootfiles => [
              {:full_path => arg, :media_type => guess_media_type(arg)}
            ]
          )
        when Array
          # TODO: spec
          set_values(
            :rootfiles => arg.keys.map { |k|
              filename = arg[k]
              {:full_path => filename, :media_type => guess_media_type(filename)}
            }
          )
        when Hash
          set_values(arg)
        end
      end

      private

      def build_xml(builder)
        builder.container :xmlns => "urn:oasis:names:tc:opendocument:xmlns:container", :version => "1.0" do
          builder.rootfiles do
            rootfiles.each do |i|
              builder.rootfile convert_to_xml_attributes(i)
            end
          end
        end
      end
    end

    attr_accessor :dir, :container

    # @param [Hash<Symbol, Object>] values the values of symbols and objects for OCF
    #
    # @example
    #   EeePub::OCF.new(
    #     :dir => '/path/to/dir',
    #     :container => 'container.opf'
    #   )
    def initialize(values)
      values.each do |k, v|
        self.send(:"#{k}=", v)
      end
    end

    # Set container
    #
    # @param [EeePub::OCF::Container or args for EeePub::OCF::Container]
    def container=(arg)
      if arg.is_a?(EeePub::OCF::Container)
        @container = arg
      else
        # TODO: spec
        @container = EeePub::OCF::Container.new(arg)
      end
    end

    # Save as OCF
    #
    # @param [String] output_path the output file path of ePub
    def save(output_path)
      output_path = File.expand_path(output_path)

      create_epub do
#         Zip::ZipFile.open(output_path, Zip::ZipFile::CREATE) do |zip|
#           # first entry MUST be uncompressed mimetype file with no file attributes
#           # mimetype_entry = Zip::ZipEntry.new(zip, 'mimetype')
#           # mimetype_entry = Zip::ZipEntry.new('mimetype', 'mimetype')
#           # mimetype_entry.compression_method = Zip::ZipEntry::STORED
#           # # mimetype_entry.externalFileAttributes = false
#           # mimetype_entry.extra = false
#           # zip.add(mimetype_entry, 'mimetype')
#           zip.add('mimetype', 'mimetype')
#           mimetype_entry = zip.get_entry('mimetype')
#           mimetype_entry.compression_method = Zip::ZipEntry::STORED

#           # add all other files
#           files = Dir.glob('**/*') - ['mimetype']
#           files.each do |path|
#             next if File.directory?(path)
#             zip.add(path, path)
#           end
#         end

        Zip::ZipOutputStream.open(output_path) do |zip|
          # first entry MUST be uncompressed mimetype file with no file attributes
          mimetype_entry = Zip::ZipEntry.new('', 'mimetype')
          mimetype_entry.gather_fileinfo_from_srcpath('mimetype')
          zip.put_next_entry(mimetype_entry, nil, nil, Zip::ZipEntry::STORED)
          mimetype_entry.get_input_stream { |is| IOExtras.copy_stream(zip, is) }

          # add all other files
          files = Dir.glob('**/*') - ['mimetype']
          files.each do |path|
            next if File.directory?(path)
            entry = Zip::ZipEntry.new('', path)
            entry.gather_fileinfo_from_srcpath(path)
            zip.put_next_entry(entry)
            entry.get_input_stream { |is| IOExtras.copy_stream(zip, is) }
          end
        end

        # FIXME: HACK! find library that does this properly
        # `zip -X0 #{output_path} mimetype`
        # Zip::Archive.open(output_path, Zip::CREATE) do |zip|
        #   # ensure mimetype is the first file in the zip
        #   # files = (['mimetype'] + Dir.glob('**/*')).uniq
        #   # FIXME: must add mimetype UNCOMPRESSED!
        #   # zip.add_file('mimetype', 'mimetype')
        #   files = Dir.glob('**/*').reject {|p| p == 'mimetype'}
        #   files.each do |path|
        #     if File.directory?(path)
        #       zip.add_dir(path)
        #     else
        #       zip.add_file(path, path)
        #     end
        #   end
        # end
      end
    end
    
    # Stream OCF
    #
    # @return [String] streaming output of the zip/epub file.
    def render
      create_epub do
        buffer = Zip::Archive.open_buffer(Zip::CREATE) do |zip|
          Dir.glob('**/*').each do |path|
            if File.directory?(path)
              zip.add_buffer(path, path)
            else
              zip.add_buffer(path, File.read(path))
            end
          end
        end

        return buffer
      end
    end

    private
    def create_epub
      FileUtils.chdir(dir) do
        File.open('mimetype', 'w') do |f|
          f << 'application/epub+zip'
        end

        meta_inf = 'META-INF'
        FileUtils.mkdir_p(meta_inf)

        container.save(File.join(meta_inf, 'container.xml'))
        yield
      end

    end
  end
end
