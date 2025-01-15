# frozen_string_literal: true

require 'tomlrb'
require 'license_finder/package_utils/github'

module LicenseFinder
  class Poetry < PackageManager
    class PoetryError < RuntimeError; end

    BSD = 'BSD'
    LICENSE_FORMAT = /^License.*::\s*(.*)$/.freeze

    def self.license_names_from_spec(spec)
      license_names = spec['license'].to_s.strip.split(' or ')
      has_unrecognized_license = false

      license_names.each do |license_name|
        license = License.find_by_name(license_name.strip)

        has_unrecognized_license ||= license.unrecognized_matcher?
      end

      return license_names if !license_names.empty? && !has_unrecognized_license

      spec
        .fetch('classifiers', [])
        .select { |c| c =~ LICENSE_FORMAT }
        .map { |c| c.gsub(LICENSE_FORMAT, '\1') }
    end

    def initialize(options = {})
      super
      @pyproject_toml = options[:pyproject_toml] || Pathname('pyproject.toml')
    end

    def current_packages
      @current_packages ||=
        parse_dependencies.reduce([]) do |memo, dep|
          memo << PoetryPackage.new(dep[:name], dep[:version], dep) if dep
          memo
        end
    end


    def ignored_groups
      @ignored_groups ||= []
    end

    def poetry_lock
      @poetry_lock ||= ::Tomlrb.load_file(possible_package_paths[0].to_s, symbolize_keys: true)
    end

    def possible_package_paths
      [project_path.join('poetry.lock'), project_path.join('pyproject.toml')]
    end

    def package_management_command
      'poetry'
    end

    def prepare_command
      'poetry install'
    end

    private

    def build_package_for(name, version, data)
      PoetryPackage.new(name, version, data)
    end

    def parse_dependencies
      library_list.map do |library|
        next if ignore_due_to_group?(library[:name])

        installed_license_info = license_info_from_installed_path(library)
        next library.merge(installed_license_info) if installed_license_info

        pypi_definition = PyPI.definition(library[:name], library[:version])

        github_license_info = license_info_from_github(pypi_definition)
        next library.merge(github_license_info) if github_license_info

        library.merge(license_info_from_spec(pypi_definition))
      end
    end

    def package_path(extracted_path, python_version, name, package_version)
      package_name = name.sub('-', '_')
      extracted_path + "/lib/Python#{python_version}/site-packages/#{package_name}-#{package_version}.dist-info"
    end

    def licenses(install_path)
      LicenseFiles.find(install_path, logger: logger).map { |plf| plf.license&.name }
    end

    def github_url(pypi_definition)
      if github_repo_url?(pypi_definition['home_page'])
        pypi_definition['home_page']
      else
        (pypi_definition['project_urls'] || {}).values.detect do |url|
          github_repo_url?(url)
        end
      end
    end

    def github_repo_url?(url)
      return false unless url

      url.include?('https://github.com/') && url.count('/') == 4
    end

    def library_list
      poetry_show = Cmd.run('poetry show')
      raise PoetryError, poetry_show[1] unless poetry_show[2].success?

      poetry_show[0].split("\n").map do |row|
        split_row = row.split(' ')
        { name: split_row[0], version: split_row[1], summary: split_row.slice(2..-1).join(' ') }
      end
    end

    def env_info
      poetry_env_info = Cmd.run('poetry env info')
      raise PoetryError, poetry_env_info[1] unless poetry_env_info[2].success?

      virtual_env_info = poetry_env_info[0].split("\nBase\n")[0]

      python_full_version = virtual_env_info.match(/Python:\s+(.+)/)[1]
      python_version = python_full_version.split('.')[0..1].join('.')

      extracted_path = virtual_env_info.match(/Path:\s+(.+)/)[1]

      [python_version, extracted_path]
    end

    def groups(package_name)
      poetry_lock[:package].find { |package| package[:name] == package_name }[:groups] || []
    end

    def license_info_from_installed_path(library)
      python_version, extracted_path = env_info
      install_path = Pathname.new(
        package_path(extracted_path, python_version, library[:name], library[:version])
      )

      { install_path: install_path, groups: groups(library[:name]) } if licenses(install_path).any?
    end

    def license_info_from_github(pypi_definition)
      github_url = github_url(pypi_definition)
      spdx_id = GitHub.license(github_url).dig('license', 'spdx_id') if github_url

      return unless github_url && spdx_id && spdx_id != 'NOASSERTION'

      {
        authors: pypi_definition['author'],
        description: pypi_definition['description'],
        homepage: github_url,
        spec_licenses: [spdx_id],
        groups: groups(pypi_definition['name'])
      }
    end

    def license_info_from_spec(pypi_definition)
      spec_licenses = self.class.license_names_from_spec(pypi_definition)
      {
        authors: pypi_definition['author'],
        description: pypi_definition['description'],
        homepage: pypi_definition['home_page'],
        spec_licenses: spec_licenses,
        groups: groups(pypi_definition['name'])
      }
    end

    def ignore_due_to_group?(package_name)
      (groups(package_name) - ignored_groups).empty?
    end
  end
end
