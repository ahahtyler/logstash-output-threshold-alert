require 'json'
require 'timeout'
require 'fileutils'
require 'aws-sdk-for-ruby'

require_relative 'rule.rb'
require_relative 'event.rb'
require_relative 'maxis.rb'
require_relative 'engine_helper.rb'

class WaterEngine

  ################################################################
  #                       CLI Methods
  ################################################################

  VERSION = "1.0.0"

  def self.start(options)
    WaterEngine.new(options).start
  end

  def self.stop(options)
    WaterEngine.new(options).stop
  end

  def self.restart(options)
    WaterEngine.new(options).restart
  end

  ################################################################
  #                        Initialization
  ################################################################
  attr_reader :options, :quit

  def initialize(options)
    @options = options

    options[:input] = JSON.parse(File.read(input)) if input?
    options[:rules] = JSON.parse(File.read(rules)) if rules?
    options[:logfile] = File.expand_path(logfile)  if logfile?
    options[:pidfile] = File.expand_path(pidfile)  if pidfile?

    Aws.config[:credentials] = Aws::OdinCredentials.new(sqs['materialset'])
    Aws.config[:region] = sqs['region']

    @sqs = Aws::SQS::QueuePoller.new(sqs['endpint'])
    @maxis = MaxisConnection.new(maxis['region'], maxis['endpoint'], maxis['materialset'])
  end

  ################################################################
  #                      Variable Methods
  ################################################################
  [:input, :rules, :pidfile, :logfile].each do |method|
    define_method "#{method}" do
      options[method]
    end

    define_method "#{method}?" do
      !options[method].nil?
    end
  end

  [:maxis, :s3, :sqs].each do |method|
    define_method "#{method}" do
      options[:input]["#{method}"]
    end
  end

  [:info, :debug, :warn, :error].each do |method|
    define_method "#{method}" do |arg|
      puts "[#{Process.pid}] [#{Time.now.utc}] [#{method.upcase}] #{arg}"
    end
  end

  def daemonize?
    options[:daemonize]
  end

  ################################################################
  #                         CLI Actions
  ################################################################
  def start
    check_pid
    daemonize if daemonize?
    write_pid
    trap_signals
    redirect_output if logfile? && daemonize?

    info "Starting Water Engine..."

    cleanedRules = rules['rules'].collect { |r| Rule.new(r) }
    validFolders = cleanedRules.collect   { |r| r.location }.flatten.uniq

    info "Created rules objects and a list of valid folders"

    @sqs.poll(wait_time_seconds: 10) do |msg|
      #event_id = JSON.parse(JSON.parse(msg.body)["Message"])["documentId"]["editId"]
      #doc_id   = JSON.parse(JSON.parse(msg.body)["Message"])["documentId"]["id"]

      eventId = "94c7ffbe-0613-4fc6-a77d-28da0cb3c53f:2017-06-30T18:38:36.606Z|us-west-2|103381878"
      docId   = "94c7ffbe-0613-4fc6-a77d-28da0cb3c53f"

      edits = @maxis.get("/issues/#{docId}/edits")

      editDetails, ticketDetails = state_of_ticket(edits, eventId)
      info "Retrieved edit and ticket details"

      info "Performing folder check."
      #next unless validFolders.include?(folder)
      info "Successfully validated folder. Moving on."

      #For each edit in the event
      editDetails['pathEdits'].each do |edit|

        #Create the event object
        event = Event.new(edit, ticketDetails, editDetails['actor'])
        info "Successfully created event: #{event}"

        info "Checking if event is a PUT"

        #Skip if the event is not a PUT
        next unless event.editAction.eql?("PUT")
        info "Generating possible rules"

        #Determine possible rules for the event
        possibleRules = cleanedRules.collect { |r| r if r.action.eql?(event.path) }.compact
        info "Generated a list of possible rules"

        #Skip if there are no possible rules
        next unless possibleRules.any?
        info "I have valid rules for the event."

        #For each possible Rule
        possibleRules.each do |rule|

          #Skip if the action parameters don't match
          info "Checking action parameters"
          next unless valid_action_parameters?(rule, event)
          info "Action parameters are good."

          #Skip if the conditional parameters don't match
          info "Checking conditional parameters"
          next unless valid_conditional_parameters?(rule, event)
          info "Conditional parameters are good"

          reaction = determine_rule_action(rule.reaction)

          info "Action payload: #{reaction}"
          #Call maxis
          @maxis.post("/issues/#{event.docId}/edits", reaction)

        end #Possible Rules

      end #PathEdits

    end #SQS

  end

  def stop

    redirect_output if logfile? && daemonize?

    info "Stopping Water Engine..."
    stop_process

  end

  def restart

    stop
    start

  end

  ################################################################
  #     DAEMONIZING, PID MANAGEMENT, and OUTPUT REDIRECTION
  ################################################################
  def daemonize
    exit if fork
    Process.setsid
    exit if fork
    Dir.chdir "/"
  end

  def redirect_output
    FileUtils.mkdir_p(File.dirname(logfile), :mode => 0755)
    FileUtils.touch logfile
    File.chmod(0644, logfile)
    $stderr.reopen(logfile, 'a')
    $stdout.reopen($stderr)
    $stdout.sync = $stderr.sync = true
  end

  def stop_process
    case get_pid
      when nil, 0
        warn "Unable to stop. Process doesn't exist."
      else
        Process.kill('QUIT', get_pid)
    end

    Timeout::timeout(10) do
      sleep 1 while File.exists?(pidfile)
    end
  end

  def write_pid
    if pidfile?
      begin
        File.open(pidfile, ::File::CREAT | ::File::EXCL | ::File::WRONLY){|f| f.write("#{Process.pid}") }
        at_exit { File.delete(pidfile) if File.exists?(pidfile) }
      rescue Errno::EEXIST
        check_pid
        retry
      end
    end
  end

  def check_pid
    if pidfile?
      case pid_status(pidfile)
        when :running, :not_owned
          warn "A server is already running. Check #{pidfile}"
          exit(1)
        when :dead
          File.delete(pidfile)
      end
    end
  end

  def get_pid
    case pid_status(pidfile)
      when :running ,:not_owned
        return ::File.read(pidfile).to_i
    end
  end

  def pid_status(pidfile)
    return :exited unless File.exists?(pidfile)
    pid = ::File.read(pidfile).to_i
    return :dead if pid == 0
    Process.kill(0, pid)
    :running
  rescue Errno::ESRCH
    :dead
  rescue Errno::EPERM
    :not_owned
  end

  ################################################################
  #                      SIGNAL HANDLING
  ################################################################
  def trap_signals
    trap(:QUIT) do   # graceful shutdown
      @quit = true
    end
  end

end
