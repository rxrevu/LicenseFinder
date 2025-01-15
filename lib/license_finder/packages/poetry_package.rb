module LicenseFinder
  class PoetryPackage < Package

    def initialize(name, version, options = {})
      super
    end

    def package_manager
      'Poetry'
    end
  end
end
