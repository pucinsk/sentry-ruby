require 'rake'
require 'rake/task'
require 'raven/integrations/tasks'

module Raven
  module Rake
    module Application
      def display_error_message(ex)
        Raven.capture_exception(
          ex,
          :transaction => top_level_tasks.join(' '),
          :logger => 'rake',
          :tags => { 'rake_task' => top_level_tasks.join(' ') }
        )
        super
      end
    end
  end
end

Rake::Application.prepend(Raven::Rake::Application)
