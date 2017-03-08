class Folder
  attr_accessor :guid, :name, :group

  def initialize(guid, name, group)
    @guid  = guid.to_s
    @name  = name.to_s
    @group = group
  end

  def has_parent?(maxis)
    @folder = maxis.get("/folders/#{@guid}") if @folder.nil?
    return @folder
  end

end
