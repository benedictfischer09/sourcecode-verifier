require 'httparty'
require 'zip'
require 'fileutils'
require 'base64'

module SourcecodeVerifier
  class GemDownloader
    include HTTParty
    base_uri 'https://rubygems.org'

    attr_reader :gem_name, :version

    def initialize(gem_name, version)
      @gem_name = gem_name
      @version = version
    end

    def download_and_extract(temp_dir)
      gem_file_path = download_gem(temp_dir)
      extract_gem(gem_file_path, temp_dir)
    end

    private

    def download_gem(temp_dir)
      gem_url = "/downloads/#{gem_name}-#{version}.gem"
      gem_file_path = File.join(temp_dir, "#{gem_name}-#{version}.gem")

      response = self.class.get(gem_url, follow_redirects: true)
      
      if response.success?
        File.open(gem_file_path, 'wb') do |file|
          file.write(response.body)
        end
        gem_file_path
      else
        raise Error, "Failed to download gem #{gem_name} version #{version}: #{response.code} #{response.message}"
      end
    end

    def extract_gem(gem_file_path, temp_dir)
      gem_extract_dir = File.join(temp_dir, 'gem_contents')
      FileUtils.mkdir_p(gem_extract_dir)

      # Extract the .gem file (which is a tar.gz archive)
      system("cd '#{gem_extract_dir}' && tar -xzf '#{gem_file_path}'", exception: true)

      # Extract the data.tar.gz which contains the actual gem files
      data_tar_path = File.join(gem_extract_dir, 'data.tar.gz')
      if File.exist?(data_tar_path)
        gem_files_dir = File.join(temp_dir, 'gem_files')
        FileUtils.mkdir_p(gem_files_dir)
        system("cd '#{gem_files_dir}' && tar -xzf '#{data_tar_path}'", exception: true)
        gem_files_dir
      else
        raise Error, "Could not find data.tar.gz in gem file"
      end
    end
  end
end