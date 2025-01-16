# frozen_string_literal: true

require 'spec_helper'

module LicenseFinder
  describe Poetry do
    subject { Poetry.new(options) }
    let(:options) { { project_path: fixture_path('poetry') } }

    it_behaves_like 'a PackageManager'

    describe '#current_packages' do
      def definition_for(item)
        name = item[:name] == 'markupsafe' ? 'MarkupSafe' : item[:name]
        JSON.pretty_generate(
          "info": {
            "author": '',
            "home_page": '',
            "license": item[:license],
            "name": name,
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
          { name: 'colorama', version: '0.4.6', license: 'BSD 3-Clause', groups: %w[main test] },
          { name: 'iniconfig', version: '2.0.0', license: 'MIT', groups: ['test'] },
          { name: 'markupsafe', version: '3.0.2', license: 'New BSD', groups: ['dev'] },
          { name: 'packaging', version: '24.2', license: 'BSD or Apache License, Version 2.0', groups: ['test'] },
          { name: 'pluggy', version: '1.5.0', license: 'MIT', groups: ['dev'] },
          { name: 'pytest', version: '8.3.4', license: 'MIT', groups: ['dev'] },
          { name: 'six', version: '1.17.0', license: 'MIT', groups: ['main'] }
        ]
      end

      let(:expected_dependencies) do
        [
          { name: 'colorama', version: '0.4.6', license: ['New BSD'], groups: %w[main test] },
          { name: 'iniconfig', version: '2.0.0', license: ['MIT'], groups: ['test'] },
          { name: 'markupsafe', version: '3.0.2', license: ['New BSD'], groups: ['dev'] },
          { name: 'packaging', version: '24.2', license: ['Apache 2.0', 'Simplified BSD'], groups: ['test'] },
          { name: 'pluggy', version: '1.5.0', license: ['MIT'], groups: ['test'] },
          { name: 'pytest', version: '8.3.4', license: ['MIT'], groups: ['test'] },
          { name: 'six', version: '1.17.0', license: ['MIT'], groups: ['main'] }
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
          markupsafe            3.0.2         markupsafe desc
          packaging             24.2          packaging desc
          pluggy                1.5.0         pluggy des
          pytest                8.3.4         pytest desc
          six                   1.17.0        six desc
        OUTPUT
      end

      let(:poetry_env_path) { fixture_path('poetry') }

      let(:poetry_env_info) do
        <<~OUTPUT
          Virtualenv
          Python:         3.12.7
          Implementation: CPython
          Path:           #{poetry_env_path}
          Executable:     #{poetry_env_path}bin/python
          Valid:          True

          Base
          Platform:   darwin
          OS:         posix
          Python:     3.12.7
          Path:       /Users/name/.asdf/installs/python/3.12.7
          Executable: /Users/name/.asdf/installs/python/3.12.7/bin/python3.12

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

      context 'when github and pypi are not used' do
        before do
          dependencies.each do |item|
            url = url_for(item[:name], item[:version])
            stub_request(:get, url).to_return(status: 404, body: {}.to_json)
          end
        end

        it 'uses the installed packages to find the licenses' do
          actual = subject.current_packages.map do |package|
            [package.name, package.version, package.licenses.map(&:name), package.groups]
          end
          expected = expected_dependencies.map do |dependency|
            next ['colorama', '0.4.6', ['unknown'], []] if dependency[:name] == 'colorama'

            [dependency[:name], dependency[:version], dependency[:license], dependency[:groups]]
          end

          expect(actual).to match_array(expected)
        end
      end

      context 'when the development dependencies are ignored' do
        before do
          options[:ignored_groups] = ['dev']
        end

        it 'only returns the "main" (default) dependencies' do
          actual = subject.current_packages.map do |package|
            [package.name, package.version, package.licenses.map(&:name), package.groups]
          end
          expected = expected_dependencies.each_with_object([]) do |dependency, dependencies|
            next unless dependency[:groups] != ['dev']

            dependencies.push(
              [dependency[:name], dependency[:version], dependency[:license], dependency[:groups]]
            )
          end
          expect(actual).to match_array(expected)
        end
      end
    end
  end
end
