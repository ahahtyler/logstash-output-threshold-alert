require 'json'

class Event

	attr_accessor :docId, :folder, :eventActor, :labels, :tags, :watchers,
				  :severity, :assigned, :editAction, :data, :path

	def initialize (  edit, ticket, actor )
		
		#Ticket & Folder Guids
		@docId = ticket['docId']
		@folder = ticket['folder']

		#Event Actor
		@eventActor = actor	
 
		#Ticket status up to event
		@labels = ticket['labels'].to_set
		@tags   = ticket['tags'].to_set
		@watchers = ticket['watchers']
		@severity = ticket['severity']
		@assigned = ticket['assigned']

		#Put or Delete
		@editAction = edit['editAction']

		#Simplified path for rule parsing
		basePath = edit['path'].match(/\/(\w*)/i)[0]

		#Event data & adjusted path
		@data = get_data( basePath, edit['data'])
		@path = basePath.eql?("/status") ? "#{basePath}-#{@data}" : basePath

	end

	def get_data(basePath, data)

		case basePath 
		when "/watchers", "/labels", "/tags"
			data['id']
		when "/extensions", "/assigneeIdentity"
			data
		end

	end


end
