# frozen_string_literal: true

require 'spec_helper'

module LicenseFinder
  describe Poetry do
    subject { Poetry.new(options) }
    let(:options) { { project_path: fixture_path('poetry') } }

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
          { name: 'colorama', version: '0.4.6', license: ['New BSD'], groups: %w[main dev] },
          { name: 'iniconfig', version: '2.0.0', license: ['MIT'], groups: %w[main dev] },
          { name: 'packaging', version: '24.2', license: ['Apache 2.0', 'Simplified BSD'], groups: ['dev'] },
          { name: 'pluggy', version: '1.5.0', license: ['MIT'], groups: ['test'] },
          { name: 'pytest', version: '8.3.4', license: ['MIT'], groups: ['test'] },
          { name: 'six', version: '1.17.0', license: ['MIT'], groups: %w[main dev] }
        ]
      end

      before do
        dependencies.each do |item|
          url = url_for(item[:name], item[:version])
          response_body = definition_for(license: item[:license], name: item[:name], version: item[:version])
          stub_request(:get, url).to_return(status: 200, body: response_body)
        end

        process_status = double(Process::Status)
        allow(process_status).to receive(:success?).and_return(true)
        allow(::LicenseFinder::SharedHelpers::Cmd).to receive(:run).with('poetry show').and_return([poetry_show, '', process_status])
        allow(::LicenseFinder::SharedHelpers::Cmd).to receive(:run).with('poetry env info').and_return([poetry_env_info, '', process_status])
      end

      let(:poetry_show) do
        <<~OUTPUT
          colorama              0.4.6         colorama desc
          iniconfig             2.0.0         iniconfig desc
          packaging             24.2          packaging desc
          pluggy                1.5.0         pluggy des
          pytest                8.3.4         pytest desc
          six                   1.17.0        six desc
        OUTPUT
      end

      let(:poetry_env_info) do
        <<~OUTPUT
          Virtualenv
          Python:         3.12.7
          Implementation: CPython
          Path:           /Users/ed/Library/Caches/pypoetry/virtualenvs/epa-insights-o1nysRTv-py3.12
          Executable:     /Users/ed/Library/Caches/pypoetry/virtualenvs/epa-insights-o1nysRTv-py3.12/bin/python
          Valid:          True

          Base
          Platform:   darwin
          OS:         posix
          Python:     3.12.7
          Path:       /Users/ed/.asdf/installs/python/3.12.7
          Executable: /Users/ed/.asdf/installs/python/3.12.7/bin/python3.12

        OUTPUT
      end

      it 'fetches each package identified in a poetry.lock' do
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

        it 'only returns the "main" (default) dependencies' do
          actual = subject.current_packages.map do |package|
            [package.name, package.version, package.licenses.map(&:name), package.groups]
          end
          expect(actual).to match_array(
            [
              ['colorama', '0.4.6', ['New BSD'], %w[main dev]],
              ['iniconfig', '2.0.0', ['MIT'], %w[main dev]],
              ['pytest', '8.3.4', ['MIT'], ['test']],
              ['pluggy', '1.5.0', ['MIT'], ['test']],
              ['six', '1.17.0', ['MIT'], %w[main dev]]
            ]
          )
        end
      end
    end

  end
end
