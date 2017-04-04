require 'amazon/sim'
require 'aws-sdk-for-ruby'
require 'rest-client'
require 'json'

require 'date'
require 'nokogiri'
require 'csv'
require_relative 'lib/folder.rb'
require_relative 'lib/service_line.rb'
require_relative 'lib/maxis_connection.rb'
require_relative 'lib/elasticsearch.rb'

def initialize_sim_api(materialSet, region)
	begin
	   credentials = Aws::OdinCredentials.new(materialSet)
	   return Amazon::SIM.new( :region            => region,
	 						   :access_key_id     => credentials.access_key_id,
							   :secret_access_key => credentials.secret_access_key)
	rescue
		puts "Sleeping for 10 seconds"
		sleep 10
		retry
	end
end

def collect_new_issues(guid)
	begin
		#TODO: This might need to be "ASSIGNED"
		#issues = @sim_conn.issues.filters(:containingFolder => [guid], 

       issues = @sim_conn.issues.filters(:assignedFolder => [guid], 
		                                 :createDate => [@yesterday, @today])
	rescue 
		puts "Sleeping for 10 seconds"
		sleep 10
		retry
	end
end

def create_label_combos
  supbt_labels = Hash.new

  label_block = @doc.css("label_config/supbt_labels/label")
  label_block.map {|node|  supbt_labels[node["name"]] = node["guid"]}

  supbt_labels["No Labels"]  = supbt_labels.values.join(" OR ")
  supbt_labels["All Labels"] = ""

  return supbt_labels
end

def create_team_list
  serviceArray = Array.new()
  @doc.css("teams/service").map do |service|
    serviceObj = ServiceLine.new(service["name"])
    service.css("group").map do |group|
      group.css("folder").map do |folder|
        name, guid = folder.css("guid").children, folder.css("name").children
        serviceObj.folders.push(Folder.new(name, guid, group["name"], @maxis))
      end
    end
    service.css("ignore_folders").map {|guid| serviceObj.ignoreFolder.push(guid.css("guid").children)}
    service.css("ignore_labels").map  {|guid| serviceObj.ignoreLabels.push(guid.css("guid").children)}
    serviceArray.push(serviceObj)
  end
  return serviceArray
end

def labelNames(guidArray)
	labelName = Array.new()
	guidArray.each {|guid| labelName << @labelHash.key(guid) if @labelHash.has_value?(guid)}
	labelName << "No Labels" if labelName.empty?
	return labelName
end

def folderName(folderGuid, serviceGroups)
	folderName, folderGroup, team = "", "", ""
	serviceGroups.each do |service|
		service.folders.each do |folder|
			folderName = folder.name if folderGuid.eql?(folder.guid)
			folderGroup = folder.group if folderGuid.eql?(folder.guid)
			team = service.name if folderGuid.eql?(folder.guid)
		end
	end
	folderName = "Unowned" if folderName.empty?
	folderGroup = "Unowned" if folderGroup.empty?
	team = "Unowned" if team.empty?
	
	return folderName, folderGroup, team
end

def generate_es_input(issues, folder, service)
  issues.each do |i|
	  
  	labelsArray = Array.new()
	i.labels.each { |l| labelsArray << l.id }
	  
    es_data_point ={ 'issue_id'      => i.id ,
                     'create_date'   => i.created.utc,
                     'touched'       => false,
                     '@timestamp'    => DateTime.now,
					 'team'          => service.name,		
                     'folder_group'  => folder.group,		
                     'folder_name'   => folder.name,
                     'folder_guid'   => folder.guid,
		             'label_guids'   => labelsArray,
		 		     'labels'        => labelNames(labelsArray),
		             'ticket_status' => "New", 
                     'touch_date'    => "",
                     'time_open'     => ""}
	@new_issues.push(es_data_point)
  end
end

def find_resolvers(serviceGroups)
   resolverHash = Hash.new
   serviceGroups.each do |service|
      service.folders.each do |folder|
  	     resolverHash[folder.guid] = ["kerberos:mollr@ANT.AMAZON.COM" , 
			 						  "kerberos:stigty@ANT.AMAZON.COM", 
			 						  "kerberos:leebob@ANT.AMAZON.COM", 
			 						  "kerberos:harnoram@ANT.AMAZON.COM", 
			 						  "kerberos:mokihana@ANT.AMAZON.COM", 
			 						  "kerberos:meekerr@ANT.AMAZON.COM", 
			 						  "kerberos:vemuvi@ANT.AMAZON.COM"]
      end
   end
   return resolverHash
end
	
@host        = 'maxis-service-prod-pdx.amazon.com'
@scheme      = 'https'
@region      = 'us-west-2'
@materialSet = 'com.amazon.credentials.isengard.968648960172.user/stigty'

@es_server = "supbtsearch.corp.amazon.com"
@es_index  = "count_metrics_test"

@input_file  = File.expand_path(File.join(File.dirname(__FILE__), "input/maxis-input.xml"))
@doc         = Nokogiri::XML(File.open(@input_file))

@today     = Time.parse(DateTime.now.strftime("%Y-%m-%dT08:00:00.000Z").to_s)
@yesterday = Time.parse((DateTime.now - 1).strftime("%Y-%m-%dT08:00:00.000Z").to_s)

@maxis    = MaxisConnection.new(@host, @scheme, @region, @materialSet)
@elastic  = Elasticsearch.new(@es_server)
@sim_conn = initialize_sim_api(@materialSet, @region)

@labelHash     = create_label_combos
serviceGroups = create_team_list
resolverHash  = find_resolvers(serviceGroups)

puts @today
puts @yesterday

@new_issues = Array.new
serviceGroups.each do |service|
  puts "Starting Searches for: #{service.name}"
  service.folders.each do |folder|
	puts "Current folder: #{folder.name}"
	  issues = collect_new_issues(folder.guid)
      generate_es_input(issues, folder, service)
  end
end

@elastic.write_to_index(@es_index, @new_issues)
sleep 10
begin
	es_results = @elastic.get_results(@es_index, "touched:(false)%20AND%20ticket_status:(Open,New)")
rescue
	es_results = Array.new
end

puts "Resutls #{es_results.count}"

es_results.each do |r|
  issue_id = r["_source"]["issue_id"]	
  beenTouched, touchDate, actor = false, "", ""

  edits = @maxis.get("/issues/#{issue_id}/edits")
  edits["edits"].each do |e|
	e["pathEdits"].each do |p|
	  if p["path"].include?("/conversation") && resolverHash[r["_source"]["folder_guid"]].include?(e["actualOriginator"])
		  actor = e["actualOriginator"]
		  touchDate = e["actualCreateDate"]
		  beenTouched = true
	  end
	end
	break if beenTouched
  end

  puts "--------"
  puts "Current Issue: #{issue_id}"
  puts "Ticket Creation Date: #{Time.parse(r["_source"]["create_date"]).utc}" #PDT timezone

  details = @maxis.get("/issues/#{issue_id}")
	
  unless details['status'].eql?(r["_source"]["ticket_status"])	
	  puts "Changing Status"
	  @elastic.update_es_item(@es_index, "ticket_status", details['status'], r["_id"])
  end

  sim_labels = Array.new
  details['labels'].each {|l| sim_labels << l['id']}
  unless sim_labels.to_set == r["_source"]["label_guids"].to_set
	  puts "Changing labels"
	  labelGuidsArray = Array.new()
	  details['labels'].each {|l| labelGuidsArray << l['id']}
	  @elastic.update_es_item(@es_index, "label_guids", labelGuidsArray, r["_id"])		
	  @elastic.update_es_item(@es_index, "labels", labelNames(labelGuidsArray), r["_id"])
  end

  unless details['assignedFolder'].eql?(r["_source"]["folder_guid"])	
	  puts "Changing folder"
	  folderName, folderGroup, team = folderName(details['assignedFolder'], serviceGroups)
	  @elastic.update_es_item(@es_index, "folder_guid", details['assignedFolder'], r["_id"])
	  @elastic.update_es_item(@es_index, "folder_name", folderName, r["_id"])
	  @elastic.update_es_item(@es_index, "folder_group", folderGroup, r["_id"])
	  @elastic.update_es_item(@es_index, "team", team, r["_id"])
  end

  if beenTouched
	  puts "Issue was touched on: #{Time.parse(touchDate).utc}" #GMT timezone
	  puts "Issue has been touched by #{actor}"
	  touchedTimeSec =  (Time.parse(touchDate).utc - Time.parse(r["_source"]["create_date"]).utc).round
	  puts "Seconds until touched #{touchedTimeSec}" 

	  @elastic.update_es_item(@es_index, "touched", "true", r["_id"])
	  @elastic.update_es_item(@es_index, "touch_date", Time.parse(touchDate).utc.to_s, r["_id"])
	  @elastic.update_es_item(@es_index, "time_open", touchedTimeSec, r["_id"])
  else
	  #If resolved and hasn't been touched put resolved date
	  if details['status'].eql?("Resolved")
		    beenResolved, resolvedDate, actor = false, "", ""
			edits["edits"].each do |e|
				e["pathEdits"].each do |p|
					if p["path"].include?("/status") && p["data"].eql?("Resolved")
					  actor = e["actualOriginator"]
					  resolvedDate = e["actualCreateDate"]
					  beenResolved = true
					end
				end
				break if beenResolved
			end

		  openTimeSec = (Time.parse(resolvedDate).utc - Time.parse(r["_source"]["create_date"]).utc).round
		  puts "Seconds issue has been Resolved: #{openTimeSec}"
		  @elastic.update_es_item(@es_index, "time_open", openTimeSec, r["_id"])
	  else
		  openTimeSec = (Time.now.utc - Time.parse(r["_source"]["create_date"]).utc).round
		  puts "Seconds issue has been untouched: #{openTimeSec}"
		  @elastic.update_es_item(@es_index, "time_open", openTimeSec, r["_id"])
	  end
	  
  end	

end
