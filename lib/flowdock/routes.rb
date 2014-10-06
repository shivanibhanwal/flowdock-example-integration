require 'sinatra/base'
require_relative 'integration'

module Flowdock
  module Routes
    module Helpers
      def oauth_connection
        Faraday.new FLOWDOCK_URL do |connection|
          connection.request :oauth2, session[:access_token]
          connection.request :json
          connection.response :json, content_type: /\bjson$/
          connection.response :logger if logger.debug?
          connection.use Faraday::Response::RaiseError
          connection.adapter Faraday.default_adapter
        end
      end
    end

    def self.registered(app)
      app.helpers Routes::Helpers

      # Setup endpoint which is configured to the application
      app.get '/flowdock/setup' do
        # Redirecting to the oauthentication with Flowdock
        # The authentication endpoint is configured in Omniauth::Builder in config/base.rb
        redirect to("/auth/flowdock?flow=#{params[:flow]}")
      end

      # Callback endpoint for successful authorizations
      app.get '/auth/flowdock/callback' do
        auth = request.env['omniauth.auth']
        omniauth_params = request.env['omniauth.params']
        session[:access_token] = auth[:credentials][:token]
        # Get the flow's information from Flowdock
        # The flow-parameter in omniauth params is the one we passed in the /flowdock/setup redirect url
        @flow = oauth_connection.get("/flows/find?id=#{omniauth_params['flow']}").body
        # Flow information contains the url for the flow, which we need for creating the integration
        slim :"flowdock/connect"
      end

      # Endpoint for failed authorizations
      app.get '/auth/failure' do
        "Oauthentication with Flowdock failed"
      end

      # Endpoint for creating the integration with the flow
      app.post '/flowdock/integrate' do
        path = URI.parse(params[:flow_url]).path

        integration = oauth_connection.post("#{path}/integrations", {
          # Name parameter can be used to communicate this particular integration, since the integration can be
          # created multiple times to one flow. In this case, we could use different categories for polls e.g.
          # work / non-work / all
          name: "All polls"
        })

        FlowdockIntegration.create!(
          token: integration.body["flow_token"], # Used for posting to the activities endpoint
          flowdock_id: integration.body["id"]    # Used for later configuration of the integration
        )

        @flow_name = params[:flow_name]
        session.delete(:access_token)
        slim :"flowdock/success"
      end

      # Endpoint for integration configuration
      app.get '/flowdock/configure' do
        integration = FlowdockIntegration.where(flodock_id: params[:integration_id])
        # Configure the integration, e.g. which actions are posted to Flowdock
      end
    end
  end
end
