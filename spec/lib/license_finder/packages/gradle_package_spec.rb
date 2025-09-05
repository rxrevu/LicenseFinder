# frozen_string_literal: true

require 'spec_helper'

module LicenseFinder
  describe GradlePackage do
    let(:spec) do
      { mavenCoordinates: {
        groupId: 'group',
        artifactId: 'a package',
        version: '1.1.1'
      } }
    end

    subject { described_class.new(JSON.parse(spec.to_json)) }

    its(:package_url) { should == 'https://plugins.gradle.org/plugin/a+package/1.1.1' }
  end
end
