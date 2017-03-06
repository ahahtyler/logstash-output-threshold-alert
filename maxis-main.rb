require 'date'
require 'nokogiri'
require 'C:\\Users\\Tyler\\Desktop\\meh\\folder.rb'
require 'C:\\Users\\Tyler\\Desktop\\meh\\service_line.rb'
require 'C:\\Users\\Tyler\\Desktop\\maxis_connection.rb'

@host        = 'maxis-service-prod-pdx.amazon.com'
@scheme      = 'https'
@region      = 'us-west-2'
@materialSet = 'com.amazon.credentials.isengard.968648960172.user/stigty'

@input_file_path = "C:\\Users\\Tyler\\Desktop\\input.xml"

def create_time_ranges
  today = DateTime.now.strftime("%Y-%m-%dT08:00:00.000Z")
  day1  = (DateTime.now - 1).strftime("%Y-%m-%dT08:00:00.000Z")
  week1 = (DateTime.now - 7).strftime("%Y-%m-%dT08:00:00.000Z")
  week2 = (DateTime.now - 14).strftime("%Y-%m-%dT08:00:00.000Z")
  week3 = (DateTime.now - 21).strftime("%Y-%m-%dT08:00:00.000Z")
  week4 = (DateTime.now - 28).strftime("%Y-%m-%dT08:00:00.000Z")
  bry   = DateTime.now.strftime("%Y-01-01T08:00:00.000Z")
  bot   = "*"

  return { 'bot' => {'start' => bot  ,  'end' => today},
           '24h' => {'start' => day1 ,  'end' => today},
           '1wk' => {'start' => week1,  'end' => today},
           '2wk' => {'start' => week2,  'end' => today},
           '3wk' => {'start' => week3,  'end' => today},
           '4wk' => {'start' => week4,  'end' => today},
           'byr' => {'start' => bry  ,  'end' => today}}
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
        serviceObj.folders.push(Folder.new(name, guid, group["name"]))
      end
    end
    service.css("ignore_folders").map {|guid| serviceObj.ignoreFolder.push(guid.css("guid").children)}
    service.css("ignore_labels").map  {|guid| serviceObj.ignoreLabels.push(guid.css("guid").children)}
    serviceArray.push(serviceObj)
  end
  return serviceArray
end

def build_payload(service, folder, dateRange, labelName, labelGuid, searchType)

  payload = ""

  #Constant fields across all searches
  payload += "folderType:(Default)"

  #Setting folder search field
  folder.has_parent?(@maxis) ? payload += "assignedFolder:" : payload += "containingFolder:"
  payload += "(#{folder.guid})"

  #Setting Time Range
  searchType.eql?("Resolved") ? payload += "lastResolvedDate:" : payload += "createDate:"
  payload += "[#{dateRange['start']} TO #{dateRange['end']}]"

  #Set Status
  payload += "status:(Open)"     if ["Open", "Actionable"].include?(searchType)
  payload += "status:(Resolved)" if ["Resolved"].include?searchType

  #Optional fields
  payload += "-containingFolder:(#{service.ignoreFolder.join(" OR ")})" unless service.ignoreFolder.empty?

  #Set up labels
  payload += "aggregatedLabels:(#{labelGuid})" if ["SupBT", "Handoff", "SysEng"].include?(labelName)

  if service.ignoreLabels.empty?
    if labelName.eql?("No Labels")
      payload += "-aggregatedLabels:(#{labelGuid})"
    end
  else
    if labelName.eql?("No Labels")
      payload += "-aggregatedLabels:(#{service.ignoreLabels.join(" OR ")} OR #{labelGuid})"
    else
      payload += "-aggregatedLabels:(#{service.ignoreLabels.join(" OR ")})"
    end
  end

  payload += "next_step.owner:role\\:resolver" if searchType.eql?("Actionable")

  return @maxis.encode(payload)
end

def store_results(results, service, folder, searchType, labelName, query, dateKey, dateRange)

end

def call_maxis(service, folder)
  @labelHash.each do |labelName, labelGuid|
    @dateHash.each do |dateKey, dateRange|
      @searchTypes.each do |searchType|
        query = build_payload(service, folder, dateRange, labelName, labelGuid, searchType)
        results = @maxis.get(query)
        puts results['totalNumberFound']
        store_results(results, service, folder, searchType, labelName, query, dateKey, dateRange)
      end
    end
  end
end

begin

  @maxis = MaxisConnection.new(@host, @scheme, @region, @materialSet)
  @doc   = Nokogiri::XML(File.open(@input_file_path))

  @labelHash   = create_label_combos
  @dateHash    = create_time_ranges
  @searchTypes = ["New Issue", "Open", "Resolved", "Actionable"]

  serviceGroups = create_team_list

  serviceGroups.each do |service|
    service.folders.each do |folder|
      call_maxis(service, folder)
    end
  end

rescue Exception => e
  puts e.backtrace
  puts e
end
