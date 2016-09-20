require 'rubygems'
require 'active_support/concern'
require 'workflow/version'
require 'workflow/specification'
require 'workflow/adapters/active_record'
require 'workflow/adapters/basic_callbacks'
require 'workflow/adapters/remodel'
require 'workflow/adapters/active_record_validations'
require 'workflow/adapters/active_support_callbacks'
require 'workflow/transition_context'

# See also README.markdown for documentation
module Workflow
  extend ActiveSupport::Concern

  included do
    include Adapter::ActiveSupportCallbacks

    # Look for a hook; otherwise detect based on ancestor class.
    if respond_to?(:workflow_adapter)
      include self.workflow_adapter
    else
      if Object.const_defined?(:ActiveRecord) && self < ActiveRecord::Base
        include Adapter::ActiveRecord
        include Adapter::ActiveRecordValidations
      end
      if Object.const_defined?(:Remodel) && klass < Adapter::Remodel::Entity
        include Adapter::Remodel::InstanceMethods
      end
    end
  end

  def current_state
    loaded_state = load_workflow_state
    res = spec.states[loaded_state.to_sym] if loaded_state
    res || spec.initial_state
  end

  # See the 'Guards' section in the README
  # @return true if the last transition was halted by one of the transition callbacks.
  def halted?
    @halted
  end

  # @return the reason of the last transition abort as set by the previous
  # call of `halt` or `halt!` method.
  def halted_because
    @halted_because
  end

  def process_event!(name, *args)
    event = current_state.events.first_applicable(name, self)
    raise NoTransitionAllowed.new(
      "There is no event #{name.to_sym} defined for the #{current_state} state") \
      if event.nil?
    @halted_because = nil
    @halted = false

    check_transition(event)

    from = current_state
    to = spec.states[event.transitions_to]
    execute_transition!(from, to, name, event, *args)
  end

  def halt(reason = nil)
    @halted_because = reason
    @halted = true
    throw :halt
  end

  def halt!(reason = nil)
    @halted_because = reason
    @halted = true
    raise TransitionHalted.new(reason)
  end

  def spec
    # check the singleton class first
    class << self
      return workflow_spec if workflow_spec
    end

    c = self.class
    # using a simple loop instead of class_inheritable_accessor to avoid
    # dependency on Rails' ActiveSupport
    until c.workflow_spec || !(c.include? Workflow)
      c = c.superclass
    end
    c.workflow_spec
  end

  private

  def has_callback?(action)
    # 1. public callback method or
    # 2. protected method somewhere in the class hierarchy or
    # 3. private in the immediate class (parent classes ignored)
    action = action.to_sym
    self.respond_to?(action) or
      self.class.protected_method_defined?(action) or
      self.private_methods(false).map(&:to_sym).include?(action)
  end

  def run_action_callback(action_name, *args)
    action = action_name.to_sym
    self.send(action, *args) if has_callback?(action)
  end

  def check_transition(event)
    # Create a meaningful error message instead of
    # "undefined method `on_entry' for nil:NilClass"
    # Reported by Kyle Burton
    if !spec.states[event.transitions_to]
      raise WorkflowError.new("Event[#{event.name}]'s " +
          "transitions_to[#{event.transitions_to}] is not a declared state.")
    end
  end


  # load_workflow_state and persist_workflow_state
  # can be overriden to handle the persistence of the workflow state.
  #
  # Default (non ActiveRecord) implementation stores the current state
  # in a variable.
  #
  # Default ActiveRecord implementation uses a 'workflow_state' database column.
  def load_workflow_state
    @workflow_state if instance_variable_defined? :@workflow_state
  end

  def persist_workflow_state(new_value)
    @workflow_state = new_value
  end

  module ClassMethods
    attr_reader :workflow_spec

    def workflow_column(column_name=nil)
      if column_name
        @workflow_state_column_name = column_name.to_sym
      end
      if !instance_variable_defined?('@workflow_state_column_name') && superclass.respond_to?(:workflow_column)
        @workflow_state_column_name = superclass.workflow_column
      end
      @workflow_state_column_name ||= :workflow_state
    end

    def workflow(meta=nil, &specification)
      meta ||= Hash.new
      assign_workflow Specification.new(meta, &specification)
    end

    private

    # Creates the convinience methods like `my_transition!`
    def assign_workflow(specification_object)
      # Merging two workflow specifications can **not** be done automically, so
      # just make the latest specification win. Same for inheritance -
      # definition in the subclass wins.
      if self.superclass.respond_to?(:workflow_spec, true)
        undefine_methods_defined_by_workflow_spec superclass.workflow_spec
      end

      @workflow_spec = specification_object
      @workflow_spec.states.values.each do |state|
        state_name = state.name
        module_eval do
          define_method "#{state_name}?" do
            state_name == current_state.name
          end
        end

        state.events.flat.each do |event|
          event_name = event.name
          module_eval do
            define_method "#{event_name}!".to_sym do |*args|
              process_event!(event_name, *args)
            end

            define_method "can_#{event_name}?" do
              return !!current_state.events.first_applicable(event_name, self)
            end
          end
        end
      end
    end

    def undefine_methods_defined_by_workflow_spec(inherited_workflow_spec)
      inherited_workflow_spec.states.values.each do |state|
        state_name = state.name
        module_eval do
          undef_method "#{state_name}?"
        end

        state.events.flat.each do |event|
          event_name = event.name
          module_eval do
            undef_method "#{event_name}!".to_sym
            undef_method "can_#{event_name}?"
          end
        end
      end
    end
  end
end
