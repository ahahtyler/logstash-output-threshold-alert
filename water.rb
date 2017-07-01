require 'set'
require 'date'
require 'json'
require 'securerandom'
require 'aws-sdk-for-ruby'
require_relative 'lib/maxis_connection.rb'
require_relative 'lib/rule.rb'
require_relative 'lib/event.rb'

def state_of_ticket(edits, eventId)
  
  event, ticket  = {}, {}

  firstEvent         = (edits['edits'][0])['pathEdits'][0]['data'] 
  ticket['tags']     = firstEvent['tags'].collect{ |t| t['id'] }
  ticket['labels']   = firstEvent['labels'].collect{ |l| l['id'] }
  ticket['watchers'] = firstEvent['watchers'].collect{ |w| w['id'] }
  ticket['assigned'] = firstEvent['assigneeIdentity'][/kerberos:(.*)@ANT.AMAZON.COM/,1] || ""
  ticket['folder']   = firstEvent['assignedFolder']
  ticket['docId']    = firstEvent['id']
  ticket['severity'] = firstEvent['extensions']['tt'].nil? ? "" : firstEvent['extensions']['tt']['impact']

  edits['edits'].each do |e|

    event['pathEdits'] = e['pathEdits']
    event['actor']     = e['actualOriginator'][/kerberos:(.*)@ANT.AMAZON.COM/,1]

    e['pathEdits'].each do |p|
      action = p['editAction']
      data   = p['data']
      path   = p['path']

      if path.include?("/watchers/")
        ticket['watchers'] << data['id'] if action.eql?("PUT")
        ticket['watchers'].delete(path.split('/').last) if action.eql?("DELETE")
      
      elsif path.include?("/labels/")
        ticket['labels'] << data['id'] if action.eql?("PUT")
        ticket['labels'].delete(path.split('/').last) if action.eql?("DELETE")

      elsif path.include?("/tags/")
        ticket['tags'] << data['id'] if action.eql?("PUT")
        ticket['tags'].delete(path.split('/').last) if action.eql?("DELETE")

      elsif path.eql?("/extensions/tt/impact")
        ticket['severity'] = data if action.eql?("PUT")
        ticket['severity'] = "" if action.eql?("DELETE")

      elsif path.eql?("/assigneeIdentity")
        ticket['assigned'] = data[/kerberos:(.*)@ANT.AMAZON.COM/,1] if action.eql?("PUT")
        ticket['assigned'] = "" if action.eql?("DELETE")

      elsif path.eql?("/assignedFolder")
        ticket['folder'] = data 

      end

    end

    break if e['id'].eql?(eventId)
  end

  return event, ticket

end

def valid_action_parameters?(rule, event)
  return true if rule.action_params.empty?
  action_params.values.eql?(event.data)
end

def valid_conditional_parameters?(rule, event)
  return true if rule.conditional_params.empty?

  process = false
  rule.conditional_params.select do |key, value|
    case key
      when 'actor'
        process = value.include?(event.eventActor)
      when 'severity'
        process = value.include?(event.severity)
      when 'assigned'
        process = value.include?(event.assigned)
      when 'watchers'
        process = (value & event.watchers).any?
      when 'labels'
        comparisons = value.collect { |labels| (labels.to_set).subset?(event.labels) }
        process = comparisons.include? true 
      when 'tag'
        comparisons = value.collect { |tags| (tags.to_set).subset?(event.tags) }
        process = comparisons.include? true
    end
    break unless process
  end
  aprocess
end

def resolve_ticket 
   payload = {
      :pathEdits => [{
          :editAction => "PUT",
          :path => "/status",
          :data => "Resolved"
        }]
    }
end

def change_folder (param)
  payload = {
    :pathEdits => [{
      :editAction => "PUT",
      :path => "/assignedFolder",
      :data => param
      }]
  } 
end

def add_label (param)
  payload = {
    :pathEdits => [{
        :editAction => "PUT",
        :path => "/labels/" + param,
        :data => {
          :id => param
        }
      }]
  }
end

def add_tag (param)
  payload = {
    :pathEdits => [{
        :editAction => "PUT",
        :path => "/tags/" + param,
        :data => {
          :id => param
        }
      }]
  }
end

def assign_user (param)
  payload = {
    :pathEdits => [{
      :editAction => "PUT",
      :path => "/assigneeIdentity",
      :data => "kerberos:" + param + "@ANT.AMAZON.COM"
      }]
  }
end

def add_watcher (param)
  payload = {
    :pathEdits => [{
      :editAction => "PUT",
      :path => "/watchers/" + param,
      :data => {
        :id => param,
        :type => "email"
      }
      }]
  }
end

def add_comment (param)
  eventGuid = SecureRandom.uuid
  payload = {
    :pathEdits => [{
        :editAction => "PUT",
        :path => "/conversation/" + eventGuid,
        :data => {
          :message => param,
          :id => eventGuid,
          :contentType => "text/amz-markdown-sim",
          :messageType => "conversation",
          :mentions => [ ]
        }
      }]
  }
end


################################################################
#                       Initialization
################################################################

@maxis = MaxisConnection.new( "maxis-service-prod-pdx.amazon.com", 
                              "us-west-2",
                              "com.amazon.credentials.isengard.968648960172.user/stigty" )

Aws.config[:credentials] = Aws::OdinCredentials.new( "com.amazon.credentials.isengard.383053360765.user/ResolveGroupNotifier" )
Aws.config[:region]      = "us-west-2"
@sqs = Aws::SQS::QueuePoller.new( "https://sqs.us-west-2.amazonaws.com/383053360765/SupBTWaterRules" )

rules_file = File.read('/home/stigty/WaterEngine/src/SupBTWater/bin/input.json')
rules = JSON.parse(rules_file)['rules']


################################################################
#                       Parse Rules
################################################################

#Parse rules from the input file
cleanedRules = rules.collect { |r| Rule.new(r) }
validFolders = cleanedRules.collect { |r| r.location }.flatten.uniq

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

  #If there are no rules for the particular folder, skip
  next unless validFolders.include?(folder)

  #For each edit in the event
  editDetails['pathEdits'].each do |edit|

    #Create the event object
    event = Event.new(edit, ticketDetails, editDetails['actor'])

    #Determine possible rules for the event
    possibleRules = cleanedRules.collect { |r| r if r.action.eql?(event.path) }.compact

    #Skip if the event is not a PUT
    next unless event.editAction.eql?("PUT") 

    #Skip if there are no possible rules
    next unless possibleRules.any?

    #For each possible Rule
    possibleRules.each do |rule|

      #Skip if the action parameters don't match
      next unless validate_action_parameters?(rule, event)

      #Skip if the conditional parameters don't match
      next unless valid_conditional_parameters?(rule, event)

      #Build payload for the reaction
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

      #Call maxis 
      @maxis.post("/issues/#{event.docId}/edits", payload)

    end #Possible Rules

  end #PathEdits

end #SQS

