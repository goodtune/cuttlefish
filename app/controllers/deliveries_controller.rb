class DeliveriesController < ApplicationController
  after_action :verify_authorized, except: :index
  after_action :verify_policy_scoped, only: :index

  def index
    @deliveries = policy_scope(Delivery)

    if params[:search]
      @search = params[:search]
      @deliveries = @deliveries.joins(:address).where("addresses.text" => @search)
    else
      @status = params[:status]
      if params[:app_id]
        @app = App.find(params[:app_id])
        @deliveries = @deliveries.where(app_id: @app.id)
        @deliveries = @deliveries.joins(:email).where("emails.app_id" => @app.id)
      end
      @deliveries = @deliveries.where(status: @status) if @status
    end

    @deliveries = @deliveries.includes(:delivery_links, :postfix_log_lines, :email, :address).order("deliveries.created_at DESC").page(params[:page])
  end

  def show
    @delivery = Delivery.find(params[:id])
    authorize @delivery
  end
end
