# frozen_string_literal: true

require 'spec_helper'

module LicenseFinder
  describe PoetryPackage do
    subject { described_class.new(nil, nil) }

    its(:package_manager) { should == 'Poetry' }
  end
end
