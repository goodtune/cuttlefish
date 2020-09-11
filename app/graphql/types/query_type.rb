# frozen_string_literal: true

module Types
  class QueryType < GraphQL::Schema::Object
    # Add root-level fields here.
    # They will be entry points for queries on your schema.
    description "The query root for the Cuttlefish GraphQL API"

    field :email, Types::Email, null: true do
      argument :id, ID, required: true, description: "ID of Email to find"
      description "Find a single Email"
    end

    field :emails, Types::EmailConnection, connection: false, null: true do
      description "A list of Emails that this admin has access to. " \
                  "Most recent emails come first."

      argument :app_id, ID,
               required: false,
               description: "Filter results by App"
      argument :status, Types::Status,
               required: false,
               description: "Filter results by Email status"
      argument :since, Types::DateTime,
               required: false,
               description: "Filter result to emails created since time"
      argument :from, String,
               required: false,
               description: "Filter results by Email from address"
      argument :to, String,
               required: false,
               description: "Filter results by Email to address"
      argument :meta_key, String,
               required: false,
               description: "Filter results by Emails with given metadata key"
      argument :meta_value, String,
               required: false,
               description: "Filter results by Emails with given metadata value"
      argument :limit, Int,
               required: false,
               description:
                "For pagination: sets maximum number of items returned"
      argument :offset, Int,
               required: false,
               description: "For pagination: sets offset"
    end

    field :app, Types::App, null: true do
      argument :id, ID, required: true, description: "ID of App to find"
      description "Find a single App"
    end

    field :apps, [Types::App], null: true do
      description "A list of Apps that this admin has access to, " \
                  "sorted alphabetically by name."
    end

    field :teams, [Types::Team], null: true do
      description "A list of all teams. Only accessible by a site admin."
    end

    field :cuttlefish_app, Types::App, null: false do
      description "The App used by Cuttlefish to send its own email"
    end

    field :configuration, Types::Configuration, null: false do
      description "Application configuration settings"
    end

    field :admins, [Types::Admin], null: false do
      description "List of Admins that this admin has access to, " \
                  "sorted alphabetically by name."
    end

    field :blocked_address, Types::BlockedAddress, null: true do
      argument :app_id, ID,
               required: false,
               description: "Filter results by App"
      argument :address, String, required: true, description: "Email address"
      description "Find whether an email address is being blocked"
    end

    # TODO: Switch over to more relay-like pagination
    field :blocked_addresses, Types::BlockedAddressConnection,
          connection: false, null: false do
      description "Auto-populated list of email addresses which bounced " \
                  "within the last week. Further emails to these addresses " \
                  "will be 'held back' and not sent"
      argument :app_id, ID,
               required: false,
               description: "Filter results by App"
      argument :limit, Int,
               required: false,
               description:
                "For pagination: sets maximum number of items returned"
      argument :offset, Int,
               required: false,
               description: "For pagination: sets offset"
    end

    field :viewer, Types::Admin, null: true do
      description "The currently authenticated admin"
    end

    guard(lambda do |_object, _args, context|
      # We always need to be authenticated
      !context[:current_admin].nil?
    end)

    def email(id:)
      email = Delivery.find_by(id: id)
      if email.nil?
        raise GraphQL::ExecutionError.new(
          "Email doesn't exist",
          extensions: { "type" => "NOT_FOUND" }
        )
      end
      email
    end

    # TODO: Switch over to more relay-like pagination
    def emails(
      app_id: nil, status: nil, since: nil, from: nil, to: nil,
      meta_key: nil, meta_value: nil,
      limit: 10, offset: 0
    )
      emails = Pundit.policy_scope(context[:current_admin], Delivery)
      emails = emails.where(app_id: app_id) if app_id
      emails = emails.where(status: status) if status
      emails = emails.where("deliveries.created_at > ?", since) if since
      emails = emails.joins(email: :meta_values).where(meta_values: { key: meta_key }) if meta_key
      emails = emails.joins(email: :meta_values).where(meta_values: { value: meta_value }) if meta_value
      if from
        address = Address.find_or_initialize_by(text: from)
        emails = emails.from_address(address)
      end
      if to
        address = Address.find_or_initialize_by(text: to)
        emails = emails.to_address(address)
      end
      emails = emails.order("created_at DESC")
      { all: emails, limit: limit, offset: offset }
    end

    # TODO: Generalise this to sensibly handling record not found exception
    def app(id:)
      app = ::App.find_by(id: id)
      if app.nil?
        raise GraphQL::ExecutionError.new(
          "App doesn't exist",
          extensions: { "type" => "NOT_FOUND" }
        )
      end
      app
    end

    def apps
      Pundit.policy_scope(context[:current_admin], ::App).order(:name)
    end

    def teams
      unless TeamPolicy.new(context[:current_admin], ::Team).index?
        raise GraphQL::ExecutionError.new(
          "Not authorized to access Query.teams",
          extensions: { "type" => "NOT_AUTHORIZED" }
        )
      end

      Pundit.policy_scope(context[:current_admin], ::Team)
    end

    def cuttlefish_app
      ::App.cuttlefish
    end

    def configuration
      Rails.configuration
    end

    def admins
      Pundit.policy_scope(context[:current_admin], ::Admin).order(:name)
    end

    # TODO: This is currently doing entirely the wrong thing.
    # It should return a list of entries. There could be more than one.
    def blocked_address(app_id: nil, address:)
      a = Address.find_by(text: address)
      return if a.nil?

      if app_id
        Pundit.policy_scope(context[:current_admin], AppDenyList)
              .where(address: a, app_id: app_id).first
      else
        Pundit.policy_scope(context[:current_admin], DenyList)
              .where(address: a).first
      end
    end

    def blocked_addresses(app_id: nil, limit: 10, offset: 0)
      b = Pundit.policy_scope(context[:current_admin], AppDenyList)
      b = b.where(app_id: app_id) if app_id
      b = b.order(created_at: :desc)
      { all: b, limit: limit, offset: offset }
    end

    def viewer
      context[:current_admin]
    end
  end
end
