rules = File.read('input.txt').lines

#Parse input
actions_mappings = {'ASSIGNED_LABEL' => "label",
                    'ISSUE_CREATED' => "created",
                    'ISSUE_MOVED' => "move",
                    'ISSUE_RESOLVED' => "resolve",
                    'COMMENTED_ON_BY' => "comment"}

reactions_mapping = {'RESOLVE_ISSUE' => "resolve",
                     'MOVE_ISSUE_TO' => "move",
                     'COMMENT' => "comment",
                     'ASSIGN_LABEL' => "label",
                     'ASSIGN_TAG' => "tag"}

consumable_rules = Array.new
rules.each do |r|
  action = r[/IF(.*?)(?:IN|TO)+/, 1]
  location = r[/(?:TO|IN)+(.*?)THEN/, 1]
  reaction = r[/THEN(.*)/, 1]

  raise if action.empty? || location.empty? || reaction.empty?

  aap = action.split(" ")
  rap = reaction.split(" ")

  crh = Hash.new

  crh['action']   = actions_mappings[aap.first]
  crh['reaction'] = reactions_mapping[rap.first]
  crh['a_param']  = aap.last if aap.size > 1
  crh['r_param']  = rap.last if rap.size > 1
  crh['location'] = location.split(',').each {|l| l.strip!}

  consumable_rules << crh
end

#Parse out valid action
valid_actions = consumable_rules.collect {|r| r['action'] }.uniq

#Build Events
event1 = {'action' => "label", 'param' => "label_guid", 'doc_id' => "issue_guid", 'folder_id' => "folderC"}
event2 = {'action' => "comment", 'param' => "user", 'doc_id' => "issue_guid", 'folder_id' => "folderB"}
events = [event1, event2]

#SQS Loop
events.each do |e|
  puts "Working on event: #{e.inspect}"

  #Determine the events
    # action, optional param, doc_id, folder_id

  next unless valid_actions.include?(e['action'])

  potential_rules = consumable_rules.collect{
    |r| r if r['action'].eql?(e['action'])
  }.compact

  case e['action']
    when "create", "move", "resolve"
      reactions = potential_rules.collect{|pr|
        pr if pr['location'].include?(e['folder_id'])
      }.compact
    when "comment", "label"
      reactions = potential_rules.collect{|pr|
        pr if pr['location'].include?(e['folder_id']) && pr['a_param'].eql?(e['param'])
      }.compact
  end

  reactions.each do |r|
    #Call maxis to do some task
    payload = {}
    data = ""
    path = ""

    case r['reaction']
      when "resolve"

      when "move"

      when "comment"

      when "label"

      when "tag"

    end

    puts "Going to #{r['reaction']} #{(r['r_param'].nil? ? "" : "with params #{r['r_param']}")}"
  end

end

