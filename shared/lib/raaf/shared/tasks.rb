# frozen_string_literal: true

module RAAF
  module Shared
    module Tasks
      ##
      # Load all shared rake tasks
      #
      # @param rake_app [Rake::Application] The rake application instance
      #
      def self.load_all(rake_app = Rake.application)
        tasks_dir = File.expand_path("tasks", __dir__)
        
        Dir.glob(File.join(tasks_dir, "*.rake")).each do |task_file|
          rake_app.add_import(task_file)
        end
      end
      
      ##
      # Load specific rake task
      #
      # @param task_name [String] Name of the task file (without .rake extension)
      # @param rake_app [Rake::Application] The rake application instance
      #
      def self.load(task_name, rake_app = Rake.application)
        task_file = File.expand_path("tasks/#{task_name}.rake", __dir__)
        
        if File.exist?(task_file)
          rake_app.add_import(task_file)
        else
          raise "Task file not found: #{task_file}"
        end
      end
    end
  end
end