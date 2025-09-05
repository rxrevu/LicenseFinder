# frozen_string_literal: true

module LicenseFinder
  class GradlePackage < Package
    def initialize(spec, options = {})
      group = spec['mavenCoordinates']['groupId']
      name = spec['mavenCoordinates']['artifactId']
      version = spec['mavenCoordinates']['version']

      name = options[:include_groups] ? "#{group}:#{name}" : name

      licenses = spec['licenses']
        &.map { |l| l['spdxLicenseIdentifier'] || l['name'] }
        &.reject { |reject_name| reject_name == 'No license found' }

      super(name, version, options.merge(spec_licenses: licenses))
    end

    def package_manager
      'Gradle'
    end

    def package_url
      "https://plugins.gradle.org/plugin/#{CGI.escape(name)}/#{CGI.escape(version)}"
    end
  end
end
