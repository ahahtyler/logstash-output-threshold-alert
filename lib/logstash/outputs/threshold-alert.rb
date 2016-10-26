# encoding: utf-8
require "logstash/outputs/base"
require "logstash/namespace"
require "mail"
require "open3"

# An example output that does nothing.
class LogStash::Outputs::ThresholdAlert < LogStash::Outputs::Base
  config_name "threshold_alert"

  #Email info
  config :to,             :validate => :string, :required => true
  config :from,           :validate => :string, :default => "logstash.alert@nowhere.com"
  config :cc,             :validate => :string
  config :subject, 		    :validate => :string,  :default => ""
  config :body, 		      :validate => :string,  :default => ""

  #Eamil setting
  config :via, 			      :validate => :string,  :default => "smtp"
  config :address,  	    :validate => :string,  :default => "localhost"
  config :port, 		      :validate => :number,  :default => 25
  config :domain, 		    :validate => :string,  :default => "localhost"
  config :username, 	    :validate => :string
  config :password, 	    :validate => :string
  config :authentication, :validate => :string
  config :use_tls, 		    :validate => :boolean, :default => false

  #Jira info
  config :jira_title,     :validate => :string
  config :jira_body,      :validate => :string
  config :jira_watchers,  :validate => :string

  #Jira settings
  config :jira_user,      :validate => :string
  config :jira_password,  :validate => :string
  config :jira_project,   :validate => :string
  config :jira_url,       :validate => :string
  config :add_to_ticket,  :validate => :string
  config :same_ticket,    :validate => :boolean

  #Shell info
  config :shell_commands, :validate => :array

  #Threshold values
  config :wait_period,    :validate => :number,  :default => 600
  config :minimum_events, :validate => :number,  :default => 0

  public
  def register

    @shell_commands.nil? ? @shell=false : @shell=true
    @jira_url.nil?       ? @jira =false : @jira =true
    @to.nil?             ? @email=false : @email=true

    #############################################
    options = {
      :address              => @address,
      :port                 => @port,
      :domain               => @domain,
      :user_name            => @username,
      :password             => @password,
      :authentication       => @authentication,
      :enable_starttls_auto => @use_tls,
    }

    if @via == 'smpt'
      Mail.defaults { delivery_method :smtp, options }
    elsif @via == 'sendmail'
      Mail.defaults { delivery_method :sendmail }
    else
      Mail.defaults { delivery_method :@via, options }
    end
    #############################################
    #Get all of the shell commands

    #############################################
    #Validate Jira account

    #############################################
    @start_time    = Time.now.to_i
    @next_check    = @start_time + @wait_period
    @event_counter = 0
    #############################################

  end # def register

  public
  def receive(event)

    @event_counter += 1

    if @next_check < Time.now.to_i

      if @event_counter <= @minimum_events

        send_email         if @email
        create_jira_ticket if @jira
        execute_shell      if @shell

      end

      @start_time    = Time.now.to_i
      @next_check    = @start_time + @wait_period
      @event_counter = 0

    end
  
    return event

  end # def event

  public
  def send_email
    mail         = Mail.new
    mail.from    = @from
    mail.to      = @to
    mail.cc      = @cc
    mail.subject = @subject
    mail.body    = @body.gsub!(/\\n/, "\n")

    begin
      mail.deliver!
    rescue StandardError => e
      @logger.error("Something happen while delivering an email", :exception => e)
    end
  end

  public
  def create_jira_ticket

  end

  public
  def execute_shell

    @commands.each do |command|
      stdout, stderr, status = Open3.capture3(command)
      @logger.warn("Stdout: #{stdout}. Stderr: #{stderr}. Status: #{status}")
    end

  end

end # class LogStash::Outputs::Example
