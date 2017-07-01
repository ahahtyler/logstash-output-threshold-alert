require 'set'
require 'date'
require 'json'
require 'aws-sdk-for-ruby'
require_relative 'lib/rule.rb'
require_relative 'lib/event.rb'
require_relative 'lib/water_helper.rb'
require_relative 'lib/maxis_connection.rb'

include WaterEngineHelper

################################################################
#                       Initialization
################################################################

@logger = WaterEngineHelper.class_variable_get(:@@logger)

@maxis = MaxisConnection.new( "maxis-service-prod-pdx.amazon.com", 
                              "us-west-2",
                              "com.amazon.credentials.isengard.968648960172.user/stigty" )

Aws.config[:credentials] = Aws::OdinCredentials.new( "com.amazon.credentials.isengard.383053360765.user/ResolveGroupNotifier" )
Aws.config[:region]      = "us-west-2"
@sqs = Aws::SQS::QueuePoller.new( "https://sqs.us-west-2.amazonaws.com/383053360765/SupBTWaterRules" )

rules_file = File.read('/home/stigty/WaterEngine/src/SupBTWater/bin/input.json')
rules = JSON.parse(rules_file)['rules']

puts "Successfully read in rules"

################################################################
#                       Parse Rules
################################################################

#Parse rules from the input file
cleanedRules = rules.collect { |r| Rule.new(r) }
validFolders = cleanedRules.collect { |r| r.location }.flatten.uniq

puts "Created rules objects and a list of valid folders"
################################################################
#                   SQS Event Consumer
################################################################

@sqs.poll(wait_time_seconds: 10) do |msg|
  
  #event_id = JSON.parse(JSON.parse(msg.body)["Message"])["documentId"]["editId"]
  #doc_id   = JSON.parse(JSON.parse(msg.body)["Message"])["documentId"]["id"]

  eventId = "94c7ffbe-0613-4fc6-a77d-28da0cb3c53f:2017-06-30T18:38:36.606Z|us-west-2|103381878"
  docId   = "94c7ffbe-0613-4fc6-a77d-28da0cb3c53f"

  #Get audit trail from SIM
  edits = @maxis.get("/issues/#{docId}/edits")

  #Determine the state of the Ticket & get Edits in event
  editDetails, ticketDetails = state_of_ticket(edits, eventId)
  puts "Retrieved edit and ticket details"
  puts "-------"
  puts editDetails
  puts "-------"
  puts ticketDetails
  puts "-------"

  #If there are no rules for the particular folder, skip
  puts "Performing folder check."
  #next unless validFolders.include?(folder)
  puts "Successfully validated folder. Moving on. "

  #For each edit in the event
  editDetails['pathEdits'].each do |edit|

    #Create the event object
    event = Event.new(edit, ticketDetails, editDetails['actor'])
    puts "Successfully created event: #{event}"

    puts "Checking if event is a PUT"

    #Skip if the event is not a PUT
    next unless event.editAction.eql?("PUT") 
    puts "Generating possible rules"

    #Determine possible rules for the event
    possibleRules = cleanedRules.collect { |r| r if r.action.eql?(event.path) }.compact
    puts "Generated a list of possible rules"

    #Skip if there are no possible rules
    next unless possibleRules.any?
    puts "I have valid rules for the event."

    #For each possible Rule
    possibleRules.each do |rule|

      #Skip if the action parameters don't match
      puts "Checking action parameters"
      next unless valid_action_parameters?(rule, event)
      puts "Action parameters are good."

      #Skip if the conditional parameters don't match
      puts "Checking conditional parameters"
      next unless valid_conditional_parameters?(rule, event)
      puts "Conditional parameters are good"

      #Build payload for the reaction
      puts "Determining what aciton to run"
      case rule.reaction
        when "/status-Resolved"
          payload = resolve_ticket
        when "/assignedFolder"
          payload = change_folder(rule.reaction_params['folder'])
        when "/labels"
          payload = add_label(rule.reaction_params['label'])
        when "/tags"
          payload = add_tag(rule.reaction_params['tag'])
        when "/assigneeIdentity"
          payload = assign_user(rule.reaction_params['assignee'])
        when "/watchers"
          payload = add_watcher(rule.reaction_params['watcher'])
        when "/conversation"
          payload = add_comment(rule.reaction_params['message'])
      end

      puts "Action payload: #{payload}"
      #Call maxis 
      @maxis.post("/issues/#{event.docId}/edits", payload)
      sleep 100000
    end #Possible Rules

  end #PathEdits

end #SQS

