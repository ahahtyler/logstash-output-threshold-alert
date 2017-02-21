require 'csv'
require 'URI'

begin

  url_array = Array.new
  CSV.foreach("C:\\Users\\Tyler\\Desktop\\input.csv", :headers=> true) do |row|
    url_array.push(row['url'])
  end

  search_params_array = Array.new

  url_array.each do |url|

    issue_search_url = "https://issues.amazon.com/issues/search?q="
    sim_search_url = "https://sim.amazon.com/issues/search?q="

    search_url = issue_search_url if url.include?(issue_search_url)
    search_url = sim_search_url if url.include?(sim_search_url)

    decode = URI.decode(url)
    raw_search_params = decode[search_url.length..-1]
    raw_search_params_array = raw_search_params.scan(/-?[a-zA-Z]*:\([^);]+\)/)

    param_array = Array.new
    raw_search_params_array.each do |param|
        search_item = param.tr(')','').split(':(')
        param_hash = {'key' => search_item[0], 'value' => search_item[1]}
        param_array.push(param_hash)
    end

    search_params_array.push(param_array)

  end


  puts "label, nextStepOwner, title, containingFolder, assignedFolder, createDate, lastResolvedDate, folderType, status, assignee "
  search_params_array.each do |p_array|

    str = ""

    found = false
    p_array.each do |item|
      if item['key'].include?("label")
        str = str + item['value'] + ","
        found = true
        break
      else
        found = false
      end
    end
    str = str + " ," if found == false


    p_array.each do |item|
      if item['key'].include?("nextStepOwner")
        str = str + item['value'] + ","
        found = true
        break
      else
        found = false
      end
    end
    str = str + " ," if found == false

    p_array.each do |item|
      if item['key'].include?("title")
        str = str + item['value'] + ","
        found = true
        break
      else
        found = false
      end
    end
    str = str + " ," if found == false
    p_array.each do |item|
      if item['key'].include?("containingFolder")
        str = str + item['value'] + ","
        found = true
        break
      else
        found = false
      end
    end
    str = str + " ," if found == false

    p_array.each do |item|
      if item['key'].include?("assignedFolder")
        str = str + item['value'] + ","
        found = true
        break
      else
        found = false
      end
    end
    str = str + " ," if found == false

    p_array.each do |item|
      if item['key'].include?("createDate")
        str = str + item['value'] + ","
        found = true
        break
      else
        found = false
      end
    end
    str = str + " ," if found == false

    p_array.each do |item|
      if item['key'].include?("lastResolvedDate")
        str = str + item['value'] + ","
        found = true
        break
      else
        found = false
      end
    end
    str = str + " ," if found == false

    p_array.each do |item|
      if item['key'].include?("folderType")
        str = str + item['value'] + ","
        found = true
        break
      else
        found = false
      end
    end
    str = str + " ," if found == false

    p_array.each do |item|
      if item['key'].include?("status")
        str = str + item['value'] + ","
        found = true
        break
      else
        found = false
      end
    end
    str = str + " ," if found == false

    p_array.each do |item|
      if item['key'].include?("assignee")
        str = str + item['value'] + ","
        found = true
        break
      else
        found = false
      end
    end
    str = str + " ," if found == false


    puts str

  end

end
