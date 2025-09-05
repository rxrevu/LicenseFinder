# frozen_string_literal: true

module LicenseFinder
  class GradleDependencyFinder
    def initialize(project_path)
      @project_path = project_path
    end

    def dependencies
      Pathname
        .glob(@project_path.join('**', 'licenses.json'))
        .map(&:read)
    end
  end
end
