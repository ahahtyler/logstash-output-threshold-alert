class Rule

	attr_accessor :action, :location, :reaction, :action_params, :reaction_params, :conditional_params

	def initialize ( rule )
		@action = rule['action']
		@action_params = rule['action_params']
		@location = rule['location']
		@reaction = rule['reaction']
		@reaction_params = rule['reaction_params']
		@conditional_params = rule['conditional_params'] 
	end

end
