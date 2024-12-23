# frozen_string_literal: true
require 'tomlrb'

module LicenseFinder
  class Poetry < PackageManager
    DEFAULT_VERSION = '3'

    def initialize(options = {})
      super
      @lockfile = options[:poetry_lock_path] || Pathname('poetry.lock')
      @python_version = options[:python_version] || DEFAULT_VERSION
    end

    def current_packages
      @current_packages ||=
        begin
          packages = {}
          each_dependency(groups: allowed_groups) do |name, data, group|
            version = canonicalize(data.fetch('version', 'unknown'))
            package = packages.fetch(key_for(name, version)) do |key|
              packages[key] = build_package_for(name, version, data)
            end
            package.groups << group
          end
          packages.values
        end
    end

    def possible_package_paths
      project_path ? [project_path.join(@lockfile)] : [@lockfile]
    end

    private

    def each_dependency(groups: [])
      dependencies = parse_dependencies(detected_package_path)
      groups.each do |group|
        dependencies.fetch(group, {}).each do |name, data|
          yield name, data, group
        end
      end
    end

    def canonicalize(version)
      version.sub(/^==/, '')
    end

    def build_package_for(name, version, data)
      PipPackage.new(
        name,
        version,
        PyPI.definition(name, version),
        children: data.fetch('dependencies', []),
      )
    end

    def key_for(name, version)
      "#{name}-#{version}"
    end

    def allowed_groups
      %w[default dev] - ignored_groups.to_a
    end

    def ignored_groups
      @ignored_groups || []
    end

    def parse_dependencies(package_path)
      poetry_lock = Tomlrb.load_file(package_path)
      packages = poetry_lock.fetch('package', []).map { |package| [package['name'], package] }.to_h

      pyproject_toml = Tomlrb.load_file("#{project_path}/pyproject.toml")
      groups = pyproject_toml.dig('tool', 'poetry', 'group')
      groups['default'] = { 'dependencies' => pyproject_toml.dig('tool', 'poetry', 'dependencies') }
      grouped_packages = groups.keys.map { |group_name| [group_name, []] }.to_h

      groups.each do |group, dependencies|
        dependencies.each_value do |versioned_packages|
          versioned_packages.each_key do |package_name|
            package = packages.fetch(package_name, nil)
            next unless package

            grouped_packages[group] << [package_name, package]
            package.fetch('dependencies', []).each do |package_dependency|
              dependent_package_name = package_dependency.first
              grouped_packages[group] << [dependent_package_name, packages.fetch(dependent_package_name, {})]
            end
          end
        end
      end

      grouped_packages
    end

    def group(name, groups)
      groups.each do |group, dependencies|
        return group if dependencies.fetch('dependencies', {}).keys.include?(name.to_sym)
      end
      'default'
    end
  end
end
