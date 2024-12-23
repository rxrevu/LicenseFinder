# frozen_string_literal: true

require 'spec_helper'
require 'fakefs/spec_helpers'

module LicenseFinder
  describe Poetry do
    subject { Poetry.new(options) }
    let(:options) { { project_path: fixture_path('poetry-lock-with-pyproject-toml') } }

    it_behaves_like 'a PackageManager'

    describe '#current_packages' do
      def definition_for(item)
        JSON.pretty_generate(
          "info": {
            "author": '',
            "home_page": '',
            "license": item[:license],
            "name": item[:name],
            "summary": '',
            "version": item[:version]
          }
        )
      end

      def url_for(name, version)
        "https://pypi.org/pypi/#{name}/#{version}/json"
      end

      let(:dependencies) do
        [
          { name: 'colorama', version: '0.4.6', license: 'BSD 3-Clause', groups: ['dev'] },
          { name: 'iniconfig', version: '2.0.0', license: 'MIT', groups: ['dev'] },
          { name: 'packaging', version: '24.2', license: 'BSD or Apache License, Version 2.0', groups: ['dev'] },
          { name: 'pluggy', version: '1.5.0', license: 'MIT', groups: ['dev'] },
          { name: 'pytest', version: '8.3.4', license: 'MIT', groups: ['dev'] },
          { name: 'six', version: '1.17.0', license: 'MIT', groups: %w[default dev] },
        ]
      end

      let(:expected_dependencies) do
        [
          { name: 'colorama', version: '0.4.6', license: ['New BSD'], groups: ['dev'] },
          { name: 'iniconfig', version: '2.0.0', license: ['MIT'], groups: ['dev'] },
          { name: 'packaging', version: '24.2', license: ['Apache 2.0', 'BSD'], groups: ['dev'] },
          { name: 'pluggy', version: '1.5.0', license: ['MIT'], groups: ['dev'] },
          { name: 'pytest', version: '8.3.4', license: ['MIT'], groups: ['dev'] },
          { name: 'six', version: '1.17.0', license: ['MIT'], groups: %w[default dev] },
        ]
      end

      before do
        dependencies.each do |item|
          url = url_for(item[:name], item[:version])
          response_body = definition_for(license: item[:license], name: item[:name], version: item[:version])
          stub_request(:get, url).to_return(status: 200, body: response_body)
        end
      end

      it 'fetches each package identified in a Pipfile.lock' do
        actual = subject.current_packages.map do |package|
          [package.name, package.version, package.licenses.map(&:name), package.groups]
        end
        expected = expected_dependencies.map do |package|
          [package[:name], package[:version], package[:license], package[:groups]]
        end
        expect(actual).to match_array(expected)
      end

      context 'when the development dependencies are ignored' do
        before do
          options[:ignored_groups] = ['dev']
        end

        it 'only returns the default dependencies' do
          actual = subject.current_packages.map do |package|
            [package.name, package.version, package.licenses.map(&:name), package.groups]
          end
          expect(actual).to match_array([['six', '1.17.0', ['MIT'], ['default']]])
        end
      end
    end

  end
end
