class ServiceLine
  attr_accessor :name, :folders, :ignoreFolder, :ignoreLabels

  def initialize(name)
    @name = name
    @folders = Array.new()
    @ignoreFolder = Array.new()
    @ignoreLabels = Array.new()
  end

end
