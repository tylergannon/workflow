module Workflow
  module Callbacks
    class TransitionCallbackMethodWrapper < TransitionCallbackWrapper
      attr_reader :calling_class

      def wrapper
        cb_object = self
        proc_string = build_proc(<<-EOF)
          arguments = [
            cb_object.send(:raw_proc).inspect,
            cb_object.send(:name_arguments_string),
            cb_object.send(:rest_param_string),
            cb_object.send(:kw_arguments_string),
            cb_object.send(:keyrest_string),
            cb_object.send(:procedure_string)].compact.join(', ')
          target.instance_eval("send(\#{arguments})")
        EOF
        p = eval(proc_string)
        return overload_equality_operator(p)
      end

      # protected

      def overload_equality_operator(outer_proc)
        raw_proc = raw_proc
        def outer_proc.raw_proc
          raw_proc
        end
        def outer_proc.==(other)
          if other.kind_of?(::Proc)
            if other.respond_to?(:raw_proc)
              self.raw_proc == other.raw_proc
            else
              self == other
            end
          elsif other.kind_of?(Symbol)
            self.raw_proc == other
          else
            false
          end
        end
        return outer_proc
      end
      def name_arguments_string
        name_params.map{|name| "name_proc.call(:#{name})"} if name_params.any?
      end

      def procedure_string
        '&callbacks' if around_callback?
      end

      def callback_method
        @meth ||= calling_class.instance_method(raw_proc)
      end

      def parameters
        callback_method.parameters
      end

      def arity
        callback_method.arity
      end
    end
  end
end
