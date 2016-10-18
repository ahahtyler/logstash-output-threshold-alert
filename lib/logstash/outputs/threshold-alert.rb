# encoding: utf-8
require "logstash/outputs/base"
require "logstash/namespace"

# An example output that does nothing.
class LogStash::Outputs::ThresholdAlert < LogStash::Outputs::Base
  config_name "threshold_alert"

  config :to,                 :validate => :string,   :required => true
  config :from,               :validate => :string,   :default => "logstash.alert@nowhere.com"
  config :cc,                 :validate => :string
  config :via, 			          :validate => :string,   :default => "smtp"
  config :address,  	        :validate => :string,   :default => "localhost"
  config :port, 		          :validate => :number,   :default => 25
  config :domain, 		        :validate => :string,   :default => "localhost"
  config :username, 	        :validate => :string
  config :password, 	        :validate => :string
  config :authentication,     :validate => :string
  config :use_tls, 		        :validate => :boolean,  :default => false
  config :debug, 		          :validate => :boolean,  :default => false
  config :subject, 		        :validate => :string,   :default => ""
  config :body, 		          :validate => :string,   :default => ""

  config :threshold_time,     :validate => :number,   :default => 600
  config :threshold_events,   :validate => :number,   :default => 100

  config :jira_key,           :validate => :string
  config :jira_url,           :validate => :string
  config :jira_user,          :validate => :string
  config :jira_password,      :validate => :string

  config :smsnumber,          :validate => :string
  config :smsprovider,        :validate => :string

  config :shell_command,      :validate => :string
  config :shell_script_path,  :validate => :string

  public
  def register

    require "mail"

    @email = false
    @sms   = false
    @jira  = false
    @shell = false

    options = {
        :address              => @address,
        :port                 => @port,
        :domain               => @domain,
        :user_name            => @username,
        :password             => @password,
        :authentication       => @authentication,
        :enable_starttls_auto => @use_tls,
        :debug                => @debug
    }

    Mail.defaults { delivery_method :smtp, options } if @via == "smtp"
    Mail.defaults { delivery_method :sendmail }      if @via == 'sendmail'
    Mail.defaults { delivery_method :@via, options } unless @via == 'smtp' && @via == 'snedmail'

    @logger.debug("Email Output Registered!", :config => options, :via => @via)

    @start_time = Time.now.to_i
    @total_time = 0
    @event_counter = 0
    @total_events = 0

  end # def register

  public
  def receive(event)

    @event_counter += 1

    if (@start_time + @threshold_time) <= Time.now.to_i

      if @event_counter <= threshold_events

        send_email    if @email
        send_jira     if @jira
        execute_shell if @shell
        sned_sms      if @sms

      end

      @total_events += @event_counter
      @total_execution_time += @threshold_time
      @event_counter = 0
      @start_time = Time.now.to_i

    end

    return "Event received"
  end # def event

  public
  def send_email

    mail = Mail.new
    mail.from = @from
    mail.to = @to
    mail.cc = @cc
    mail.subject = @subject
    mail.body = @body.gsub!(/\\n/, "\n")

    begin
      mail.deliver!
    rescue StandardError => e
      @logger.error("Something happen while delivering an email", :exception => e)
    end

  end

  public
  def send_jira

  end

  public
  def execute_shell

  end

  pubilc
  def send_sms

  end

end # class LogStash::Outputs::Example
