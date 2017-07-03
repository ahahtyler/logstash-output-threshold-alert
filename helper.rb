require 'securerandom'

module WaterEngineHelper

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
    process
  end

  def determin_rule_action(reaction)
    info "Determining what aciton to run"
    case reaction
      when "/status-Resolved"
       resolve_ticket
      when "/assignedFolder"
        change_folder(rule.reaction_params['folder'])
      when "/labels"
        add_label(rule.reaction_params['label'])
      when "/tags"
        add_tag(rule.reaction_params['tag'])
      when "/assigneeIdentity"
        assign_user(rule.reaction_params['assignee'])
      when "/watchers"
        add_watcher(rule.reaction_params['watcher'])
      when "/conversation"
        add_comment(rule.reaction_params['message'])
    end
  end

  def resolve_ticket
    {
      :pathEdits => [{
         :editAction => "PUT",
         :path => "/status",
         :data => "Resolved"
     }]
    }
  end

  def change_folder (param)
    {
      :pathEdits => [{
         :editAction => "PUT",
         :path => "/assignedFolder",
         :data => param
     }]
    }
  end

  def add_label (param)
    {
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
    {
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
    {
      :pathEdits => [{
         :editAction => "PUT",
         :path => "/assigneeIdentity",
         :data => "kerberos:" + param + "@ANT.AMAZON.COM"
     }]
    }
  end

  def add_watcher (param)
    {
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
    {
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

end
