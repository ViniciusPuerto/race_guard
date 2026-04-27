# frozen_string_literal: true

module RaceGuard
  module SharedState
    # Detects whether the current stack is inside MRI +Mutex#synchronize+ (Epic 6.3).
    #
    # Heuristic: +caller_locations+ frame basename +mutex.rb+ and label related to
    # +synchronize+. This can miss alternate implementations or differ across Ruby builds.
    module MutexStack
      module_function

      # Starts after this frame and +MutexStack+ caller so any +Mutex#synchronize+ above is visible
      # regardless of TracePoint / watcher depth.
      def mutex_protected?(skip_frames: 2)
        locs = caller_locations(skip_frames..) || []
        locs.any? { |loc| mutex_frame?(loc) }
      end

      def mutex_frame?(loc)
        return false unless loc

        lab = loc.label.to_s
        # MRI often reports +Thread::Mutex#synchronize+ as the label (path may be app code,
        # not mutex.rb).
        return true if lab.include?('Mutex#synchronize')

        File.basename(loc.path.to_s) == 'mutex.rb' && synchronize_label?(loc.label)
      end

      def synchronize_label?(label)
        lab = label.to_s
        lab == 'synchronize' || lab.include?('synchronize')
      end
    end
  end
end
