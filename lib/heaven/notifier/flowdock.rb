require "heaven/notifier/flowdock/api"
require "heaven/notifier/flowdock/message_helper"

module Heaven
  module Notifier
    # A notifier for flowdock
    class Flowdock < Notifier::Default
      include ApiClient
      include FlowdockApi
      include FlowdockMessageHelper

      ADJECTIVES = [
        'Amazing',
        'Awesome',
        'Excellent',
        'Fabulous',
        'Fantastic',
        'Fine',
        'Fortuitous',
        'Great',
        'Incredible',
        'Ineffable',
        'Marvelous',
        'Mirthful',
        'Outstanding',
        'Perfect',
        'Remarkable',
        'Smart',
        'Spectacular',
        'Splendid',
        'Stellar',
        'Stupendous',
        'Wondrous'
      ]

      def deliver(message)
        Rails.logger.info "flowdock: #{message}"
        if flow_token.nil?
          Rails.logger.error "Could not find flow token for flow #{chat_room}"
          return
        end
        message_body = {
          :flow_token => flow_token,
          :event => "activity",
          :external_thread_id => flowdock_thread_id,
          :thread => thread_data,
          :title => activity_title,
          :author => activity_author,
          :tags => tags,
          :source => {
            "application" => "Heaven",
            "icon" => ENV["FLOWDOCK_USER_AVATAR"] || build_status_avatar
          }
        }
        response = thread_client.post( "/messages", JSON.generate( message_body ), {"X-flowdock-wait-for-message": "true"})
        Rails.logger.error "State: #{state}, #{autodeploy?}"
        chat_message = "@#{chat_user}, "
        case state
        when "success"
          chat_message << "your deployment of #{repo_name} to #{environment} has been completed! #{ascii_face}\n"
          chat_message << "Please remember to monitor the relevant dashboards to make sure everything went into pipe.\n"
        when "failure"
          chat_message << "your deployment of #{repo_name} to #{environment} failed! #{ascii_face}\n"
        when "error"
          chat_message << "your deployment of #{repo_name} to #{environment} has errors! #{ascii_face}\n"
          chat_message << description unless description =~ /Deploying from Heaven/
        when "pending"
          chat_message << "#{ADJECTIVES.sample} idea! Deploying #{repo_name} to #{environment}!"
        else
          Rails.logger.error "Unhandled deployment state, #{state}"
        end
        answer_to_chat(chat_message, response.body["thread_id"])
      end

      def answer_to_chat(message, deployment_thread_id)
        Rails.logger.error "Answering to chat"
        flow = auth_client.get("/flows/find", :id => chat_room)
        params = {
          :content => "#{message} Details here: #{thread_url(flow, deployment_thread_id)}"
        }
        if !thread_id.blank?
          params[:thread_id] = thread_id
        elsif !message_id.blank?
          params[:message_id] = message_id
        end
        params[:flow] = chat_room
        Rails.logger.error "Chat params"
        Rails.logger.error params
        auth_client.chat_message(params)
      end

      def thread_id
        deployment_payload["notify"]["thread_id"]
      end

      def message_id
        deployment_payload["notify"]["message_id"]
      end

      def repo_default_branch
        data["repository"]["default_branch"]
      end

      def autodeploy?
        deployment["description"].start_with?("Auto-Deployed")
      end

      def push_api_content
        "<p>#{deployment["description"]}</p>"
      end

      def thread_data
        data = {
          :title => "Deployment ##{deployment_number} of #{repo_name} to #{environment}",
          :body => "<p>#{deployment["description"]}</p>",
          :external_url => target_url,
          :status => {
            :value => state,
            :color => thread_status_color
          },
          :fields => thread_fields
        }
        data
      end

      def thread_fields
        [
          { :label => "Repository", :value => "<a href='#{repo_url}'>#{data["repository"]["full_name"]}</a>" },
          { :label => "Deployment", :value => "#{deployment_number} (<a href='#{target_url}'>output</a>)" },
          {
            :label => "Deployed ref",
            :value => "<a href='#{repo_url("/tree/#{ref}")}'>#{ref}</a> @ " + \
              "<a href='#{repo_url("/commits/#{deployment["sha"]}")}'>#{sha}</a>"
          },
          { :label => "Environment", :value => environment },
          { :label => "Previous deployment", :value => previous_deployment_link },
          { :label => "Application", :value => repo_name },
          { :label => "Project", :value => deployment_payload["config"]["project"] || "" }
        ]
      end

      def previous_deployment_link
        deployed_sha = fetch_previous_deployment
        if deployed_sha.nil?
          "No previous deployments"
        else
          diff_link = "<a href='#{repo_url("/compare/#{deployed_sha}...#{sha}")}'>Show diff</a>"
          "<a href='#{repo_url("/commits/#{deployed_sha}")}'>#{deployed_sha}</a> (#{diff_link})"
        end
      end

      def activity_author
        {
          :name => ENV["FLOWDOCK_USER_NAME"] || "Heaven",
          :avatar => ENV["FLOWDOCK_USER_AVATAR"] || build_status_avatar,
          :email => ENV["FLOWDOCK_USER_EMAIL"] || "build@flowdock.com"
        }
      end

      def fetch_previous_deployment(page = 1)
        deployments = api.deployments(
          data["repository"]["full_name"],
          :environment => environment,
          :page => page,
          :accept => "application/vnd.github.cannonball-preview+json"
        )
        return nil if deployments.length == 0
        successfull = deployments.find do |deployment|
          deployment.id < deployment_number &&
            api.deployment_statuses(deployment.url, :accept => "application/vnd.github.cannonball-preview+json")
              .any? { |status| status.state == "success" }
        end
        if successfull.nil?
          fetch_previous_deployment(page + 1)
        else
          successfull.sha[0..7]
        end
      rescue Octokit::Error => e
        Rails.logger.error "Error with github api: #{e}"
        nil
      end

      private

      def flowdock_thread_id
        "heaven:deployment:#{data["repository"]["full_name"].gsub("/", ":")}:#{deployment_number}"
      end

      def thread_url(flow, id)
        "#{flow["web_url"]}/threads/#{id}"
      end
    end
  end
end
