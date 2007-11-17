module StateMachine

  @@specifications = {}

  class << self
    
    def specify(name = :default, &states)
      @@specifications[name] = Specifier.new(&states).to_specification
    end
    
    def new(name = :default)
      Machine.new(@@specifications[name])
    end
    
    # def reconstitute(name = :default, at_state = :default)
    #   Machine.reconstitute(@@specifications[name], at_state)
    # end
    
  end
  
private
  
  # implements the metaprogramming API for creating Specifications
  class Specifier
    
    def initialize(&states)
      instance_eval(&states)
    end
    
    def state(name, &events)
      (@states ||= []) << name
      instance_eval(&events) if events
    end
    
    def event(name)
      (@events ||= {}; @events[@states.last] ||= []) << name
    end
    
    def initial_state(name)
      @initial_state = name
    end
    
    def to_specification
      Specification.new(@states, @events, @initial_state)
    end
    
  end
  
  # describes a Machine and how it should work, can validate itself
  class Specification
    attr_reader :states, :initial_state
    def initialize(states, events, initial_state)
      @states, @events, @initial_state = states, events, initial_state
    end
    def events_for_state(state)
      @events[state]
    end
  end
  
  # an instance of an actual machine, implementing the rest?
  class Machine
    
    def initialize(specification)
      @specification = specification
      @current_state = specification.initial_state
    end
    
    def states
      @specification.states
    end
    
    def current_state
      @current_state
    end
    
    def events_for_state(state)
      @specification.events_for_state(state)
    end
    
  end
  
  # do we need classes for Actions/Events/Transitions/Etc? Perhaps
  # in specification?
  
  # don't forget the bind-mode, the ability to plug in to
  # another object and merge w/ it's API

end