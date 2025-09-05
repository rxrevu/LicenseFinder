# frozen_string_literal: true

require 'spec_helper'
require 'fakefs/spec_helpers'

module LicenseFinder
  SETTINGS_DOT_GRADLE = <<-GRADLE
    rootProject.buildFileName = 'build-alt.gradle'
  GRADLE
  describe Gradle do
    let(:options) { {} }

    subject { Gradle.new(options.merge(project_path: Pathname('/fake/path'))) }

    let(:content) { [] }

    it_behaves_like 'a PackageManager'

    describe '#current_packages' do
      before do
        allow(Dir).to receive(:chdir).with(Pathname('/fake/path')).and_return(['', '', cmd_success])
        dependencies = double(:subject_dependency_file, dependencies: content)
        expect(GradleDependencyFinder).to receive(:new).and_return(dependencies)
      end

      it 'uses the gradle wrapper, if present' do
        subject = Gradle.new(project_path: Pathname('features/fixtures/gradle-wrapper'))
        expect(Dir).to receive(:chdir).with(Pathname('features/fixtures/gradle-wrapper')).and_call_original
        allow(SharedHelpers::Cmd).to receive(:run).and_return(['/usr/local/bin/gradle

BUILD SUCCESSFUL in 0s
1 actionable task: 1 executed', '', cmd_success])
        if Platform.windows?
          expect(subject.package_management_command).to eq('gradlew.bat')
        else
          expect(subject.package_management_command).to eq('./gradlew')
        end
        subject.current_packages
      end

      it 'uses custom subject command, if provided' do
        subject = Gradle.new(gradle_command: 'subjectfoo', project_path: Pathname('/fake/path'))
        expect(Dir).to receive(:chdir).with(Pathname('/fake/path')) { |&block| block.call }
        expect(SharedHelpers::Cmd).to receive(:run).with('subjectfoo licenseReport').and_return(['', '', cmd_success])
        subject.current_packages
      end

      it 'sets the working directory to project_path, if provided' do
        subject = Gradle.new(project_path: Pathname('/Users/foo/bar'))
        expect(Dir).to receive(:chdir).with(Pathname('/Users/foo/bar')) { |&block| block.call }
        if Platform.windows?
          expect(SharedHelpers::Cmd).to receive(:run).with('gradle.bat licenseReport').and_return(['', '', cmd_success])
        else
          expect(SharedHelpers::Cmd).to receive(:run).with('gradle licenseReport').and_return(['', '', cmd_success])
        end
        subject.current_packages
      end

      context 'when dependencies are found' do
        let(:content) do
          [
            JSON.dump(
              [
                {
                  mavenCoordinates: {
                    groupId: 'org.springframework',
                    artifactId: 'spring-aop',
                    version: '4.0.1.RELEASE'
                  }
                }, {
                  mavenCoordinates: {
                    groupId: 'org.springframework',
                    artifactId: 'spring-core',
                    version: '4.0.1.RELEASE'
                  }
                }
              ]
            )
          ]
        end

        it 'lists all dependencies' do
          expect(subject.current_packages.map(&:name)).to eq %w[spring-aop spring-core]
        end

        context 'when gradle group ids option is enabled' do
          let(:options) { { gradle_include_groups: true } }

          it 'lists the dependencies with the group id' do
            expect(subject.current_packages.map(&:name)).to eq %w[org.springframework:spring-aop org.springframework:spring-core]
          end
        end
      end

      context 'when multiple licenses exist' do
        let(:content) do
          [
            JSON.dump(
              [
                {
                  mavenCoordinates: {
                    groupId: '',
                    artifactId: '',
                    version: ''
                  },
                  licenses: [
                    { spdxLicenseIdentifier: 'License 1' },
                    { spdxLicenseIdentifier: 'License 2' }
                  ]
                }
              ]
            )
          ]
        end

        it 'lists all dependencies' do
          package = subject.current_packages.first
          expect(package.licenses.map(&:name)).to eq ['License 1', 'License 2']
        end
      end

      context 'when no licenses exist' do
        let(:content) do
          [
            JSON.dump(
              [
                {
                  mavenCoordinates: {
                    groupId: 'org.springframework',
                    artifactId: 'spring-aop',
                    version: '4.0.1.RELEASE'
                  }
                }
              ]
            )
          ]
        end

        it 'returns unknown' do
          expect(subject.current_packages.first.licenses.map(&:name)).to eq ['unknown']
        end
      end

      context 'when no spdx identifier provided' do
        let(:content) do
          [
            JSON.dump(
              [
                {
                  mavenCoordinates: {
                    groupId: 'com.auth0',
                    artifactId: 'auth0',
                    version: '2.24.0'
                  },
                  licenses: [
                    {
                      spdxIdentifier: nil,
                      name: 'The MIT License (MIT)'
                    }
                  ]
                }
              ]
            )
          ]
        end

        it 'returns the license' do
          expect(subject.current_packages.first.licenses.map(&:name)).to eq ['MIT']
        end
      end

      context 'when multiple license files exist' do
        let(:content) do
          [
            JSON.dump(
              [
                {
                  mavenCoordinates: {
                    groupId: 'junit',
                    artifactId: 'junit',
                    version: '4.12'
                  }
                }
              ]
            ),
            JSON.dump(
              [
                {
                  mavenCoordinates: {
                    groupId: 'org.mockito',
                    artifactId: 'mockito-core',
                    version: '1.9.5'
                  }
                }
              ]
            )
          ]
        end

        it 'lists all dependencies' do
          expect(subject.current_packages.map(&:name)).to eq %w[junit mockito-core]
        end

        context 'and there are duplicate dependencies' do
          let(:content) do
            [
              JSON.dump(
                [
                  {
                    mavenCoordinates: {
                      groupId: 'junit',
                      artifactId: 'junit',
                      version: '4.12'
                    }
                  }
                ]
              ),
              JSON.dump(
                [
                  {
                    mavenCoordinates: {
                      groupId: 'org.mockito',
                      artifactId: 'mockito-core',
                      version: '1.9.5'
                    }
                  }
                ]
              ),
              JSON.dump(
                [
                  {
                    mavenCoordinates: {
                      groupId: 'org.mockito',
                      artifactId: 'mockito-core',
                      version: '1.9.5'
                    }
                  }
                ]
              )
            ]
          end

          it 'removes duplicates' do
            expect(subject.current_packages.map(&:name)).to eq %w[junit mockito-core]
          end
        end
      end
    end

    describe '#active?' do
      include FakeFS::SpecHelpers

      context 'when dealing with root gradle project' do
        context "when there's a build.gradle" do
          it 'returns true' do
            FakeFS do
              FileUtils.mkdir_p '/fake/path'
              FileUtils.touch '/fake/path/build.gradle'

              expect(subject.active?).to be true
            end
          end
        end

        context "when there's no build.gradle or build.gradle.kts" do
          it 'returns false' do
            expect(subject.active?).to be false
          end
        end

        context "when there's build.gradle.kts" do
          it 'return true' do
            FakeFS do
              FileUtils.mkdir_p '/fake/path'
              FileUtils.touch '/fake/path/build.gradle.kts'

              expect(subject.active?).to be true
            end
          end
        end

        context "when there's a settings.gradle" do
          it 'uses the build.gradle referenced inside' do
            FakeFS do
              FileUtils.mkdir_p '/fake/path'
              File.open('/fake/path/settings.gradle', 'w') do |file|
                file.write SETTINGS_DOT_GRADLE
              end
              FileUtils.touch '/fake/path/build-alt.gradle'

              expect(subject.active?).to be true
            end
          end
        end
      end
    end

    describe '#project_root??' do
      include FakeFS::SpecHelpers

      context 'when dealing with root gradle project' do
        context "when there's a build.gradle" do
          it 'returns true' do
            FakeFS do
              FileUtils.mkdir_p '/fake/path'
              FileUtils.touch '/fake/path/build.gradle'

              expect(SharedHelpers::Cmd).to receive(:run).with("gradle -Dorg.gradle.jvmargs=-Xmx6144m properties | grep 'parent: '").and_call_original

              expect(subject.project_root?).to be true
            end
          end
        end

        context "when there's no build.gradle or build.gradle.kts" do
          it 'returns false' do
            FakeFS do
              FileUtils.mkdir_p '/fake/path'
              expect(SharedHelpers::Cmd).not_to receive(:run).with("gradle -Dorg.gradle.jvmargs=-Xmx6144m properties | grep 'parent: '")
              expect(subject.project_root?).to be false
            end
          end
        end

        context "when there's build.gradle.kts" do
          it 'return true' do
            FakeFS do
              FileUtils.mkdir_p '/fake/path'
              FileUtils.touch '/fake/path/build.gradle.kts'

              expect(SharedHelpers::Cmd).to receive(:run).with("gradle -Dorg.gradle.jvmargs=-Xmx6144m properties | grep 'parent: '").and_call_original

              expect(subject.project_root?).to be true
            end
          end
        end

        context "when there's a settings.gradle" do
          it 'uses the build.gradle referenced inside' do
            FakeFS do
              FileUtils.mkdir_p '/fake/path'
              File.open('/fake/path/settings.gradle', 'w') do |file|
                file.write SETTINGS_DOT_GRADLE
              end
              FileUtils.touch '/fake/path/build-alt.gradle'

              expect(SharedHelpers::Cmd).to receive(:run).with("gradle -Dorg.gradle.jvmargs=-Xmx6144m properties | grep 'parent: '").and_call_original

              expect(subject.project_root?).to be true
            end
          end
        end
      end

      context 'when dealing with a gradle subproject' do
        it 'returns false' do
          FakeFS do
            FileUtils.mkdir_p '/fake/path'
            FileUtils.touch '/fake/path/build.gradle'

            expect(SharedHelpers::Cmd).to receive(:run).with("gradle -Dorg.gradle.jvmargs=-Xmx6144m properties | grep 'parent: '")
                                            .and_return(["parent: root project 'parent-gradle-project'\n", nil, cmd_success])
            expect(subject.project_root?).to eq(false)
          end
        end
      end

      context 'when fetching module properties fail' do
        it 'raises an error' do
          FakeFS do
            FileUtils.mkdir_p '/fake/path'
            FileUtils.touch '/fake/path/build.gradle'

            expect(SharedHelpers::Cmd).to receive(:run).with("gradle -Dorg.gradle.jvmargs=-Xmx6144m properties | grep 'parent: '").and_return([nil, 'error', cmd_failure])

            expect { subject.project_root? }.to raise_error(%r{Command 'gradle -Dorg.gradle.jvmargs=-Xmx6144m properties \| grep 'parent: '' failed to execute in /fake/path: error})
          end
        end
      end
    end
  end
end
