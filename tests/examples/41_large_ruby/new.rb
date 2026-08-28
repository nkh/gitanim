# frozen_string_literal: true

# Refactored OrdersController — a "skinny controller" that delegates to
# service objects, concerns, and form objects. Each public action is a few
# lines of orchestration.

class OrdersController < ApplicationController
  include Controllers::OrderAnalytics
  include Controllers::OrderExports

  before_action :authenticate_user!
  before_action :set_order, only: %i[show edit update destroy cancel refund invoice reorder]

  # GET /orders
  def index
    result = OrderQueries::Index.call(user: current_user, params: params)
    assign_index_ivars(result)
    respond_with_orders(result.orders)
  end

  # GET /orders/:id
  def show
    @presenter = OrderPresenter.new(@order)
    respond_to do |format|
      format.html
      format.json { render json: OrderSerializer.new(@order).as_json }
    end
  end

  # GET /orders/new
  def new
    @form = OrderForms::Create.new(user: current_user)
    @addresses = current_user.addresses
    @payment_methods = current_user.payment_methods.active
  end

  # POST /orders
  def create
    @form = OrderForms::Create.new(user: current_user, params: order_create_params)
    result = CheckoutService.call(form: @form)

    if result.success?
      redirect_to result.order, notice: 'Order placed successfully.'
    else
      @addresses = current_user.addresses
      @payment_methods = current_user.payment_methods.active
      flash.now[:error] = result.error_message
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /orders/:id
  def update
    authorize! :update, @order
    result = OrderUpdateService.call(order: @order, params: order_params)
    if result.success?
      redirect_to @order, notice: 'Order updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /orders/:id
  def destroy
    authorize! :destroy, @order
    result = OrderDeletionService.call(order: @order)
    if result.success?
      redirect_to orders_path, notice: 'Order deleted.'
    else
      redirect_to @order, alert: result.error_message
    end
  end

  # POST /orders/:id/cancel
  def cancel
    result = OrderCancellationService.call(order: @order, user: current_user)
    if result.success?
      redirect_to @order, notice: 'Order cancelled.'
    else
      redirect_to @order, alert: result.error_message
    end
  end

  # POST /orders/:id/refund
  def refund
    result = OrderRefundService.call(order: @order, user: current_user)
    if result.success?
      redirect_to @order, notice: 'Order refunded.'
    else
      redirect_to @order, alert: result.error_message
    end
  end

  # GET /orders/:id/invoice
  def invoice
    respond_to do |format|
      format.pdf do
        pdf = InvoicePdf.new(@order)
        send_data pdf.render, filename: "invoice-#{@order.id}.pdf",
                  type: 'application/pdf', disposition: 'inline'
      end
      format.html { render :invoice, layout: 'print' }
    end
  end

  # POST /orders/:id/reorder
  def reorder
    result = ReorderService.call(order: @order, user: current_user)
    if result.success?
      redirect_to cart_path, notice: 'Items added to cart.'
    else
      redirect_to orders_path, alert: result.error_message
    end
  end

  private

  def set_order
    @order = OrderQueries::ForUser.find(current_user, params[:id])
    return if @order
    redirect_to orders_path, alert: 'Order not found.'
  end

  def order_params
    params.require(:order).permit(:notes, :gift_wrap, :shipping_method,
                                  :shipping_address_id, :billing_address_id)
  end

  def order_create_params
    params.require(:order).permit(:notes, :gift_wrap, :shipping_method,
                                  :shipping_address_id, :billing_address_id,
                                  :payment_method_id, :discount_code)
  end

  def assign_index_ivars(result)
    @orders = result.orders
    @total_spent = result.total_spent
    @pending_count = result.pending_count
  end

  def respond_with_orders(orders)
    respond_to do |format|
      format.html
      format.json { render json: orders }
      format.csv { send_data OrderCsvExporter.call(orders), filename: csv_filename, type: 'text/csv' }
    end
  end

  def csv_filename
    "orders-#{Date.today}.csv"
  end
end

# =====================================================================
# Concerns (mixins) extracted from the controller
# =====================================================================

module Controllers
  module OrderAnalytics
    def analytics
      @report = OrderAnalyticsReport.new(
        user: current_user,
        start_date: parse_date(params[:start_date], 30.days.ago.to_date),
        end_date: parse_date(params[:end_date], Date.today)
      ).build
      respond_to do |format|
        format.html
        format.json { render json: @report }
      end
    end

    private

    def parse_date(value, default)
      return default if value.blank?
      Date.parse(value)
    rescue ArgumentError
      default
    end
  end

  module OrderExports
    def export
      orders = OrderQueries::ForUser.all(current_user)
      send_data OrderCsvExporter.call(orders), filename: csv_filename, type: 'text/csv'
    end
  end
end

# =====================================================================
# Form object — encapsulates validation for order creation
# =====================================================================

class OrderForms::Create
  include ActiveModel::Model

  attr_accessor :user, :notes, :gift_wrap, :shipping_method,
                :shipping_address_id, :billing_address_id,
                :payment_method_id, :discount_code

  validates :shipping_address_id, :billing_address_id, :payment_method_id, presence: true
  validate :addresses_belong_to_user
  validate :payment_method_belongs_to_user
  validate :cart_is_not_empty

  def initialize(user:, params: {})
    @user = user
    assign_attributes(params)
  end

  def cart
    @cart ||= user.cart
  end

  def shipping_address
    @shipping_address ||= user.addresses.find_by(id: shipping_address_id)
  end

  def billing_address
    @billing_address ||= user.addresses.find_by(id: billing_address_id)
  end

  def payment_method
    @payment_method ||= user.payment_methods.find_by(id: payment_method_id)
  end

  def discount
    return @discount if defined?(@discount)
    @discount = discount_code.present? ? DiscountCode.find_by(code: discount_code.upcase) : nil
  end

  private

  def assign_attributes(params)
    params.each { |key, value| public_send("#{key}=", value) }
  end

  def addresses_belong_to_user
    %i[shipping_address billing_address].each do |attr|
      errors.add(attr, 'is invalid') unless public_send(attr)
    end
  end

  def payment_method_belongs_to_user
    errors.add(:payment_method_id, 'is invalid') unless payment_method&.active?
  end

  def cart_is_not_empty
    errors.add(:base, 'Cart is empty') if cart.line_items.empty?
  end
end

# =====================================================================
# Service objects — single-purpose business operations
# =====================================================================

class CheckoutService
  Result = Struct.new(:success?, :order, :error_message, keyword_init: true)

  def self.call(form:)
    new(form).call
  end

  def initialize(form)
    @form = form
    @order = Order.new(user_id: @form.user.id, status: 'pending')
  end

  def call
    return failure(@form.errors.full_messages.to_sentence) unless @form.valid?
    return failure('Discount code is invalid') unless discount_valid?

    ActiveRecord::Base.transaction do
      build_line_items
      apply_discount
      compute_tax_and_shipping
      @order.save!
      charge_payment
      decrement_inventory
      clear_cart
      track_discount_usage
      send_emails
      track_analytics
    end
    success(@order)
  rescue StandardError => e
    Rails.logger.error("Checkout failed: #{e.class}: #{e.message}")
    failure(e.message)
  end

  private

  def build_line_items
    @form.cart.line_items.each do |item|
      @order.line_items.build(
        product_id: item.product_id,
        quantity: item.quantity,
        unit_price: item.product.price,
        total_price: item.product.price * item.quantity
      )
    end
    @order.subtotal = @order.line_items.sum(&:total_price)
  end

  def apply_discount
    discount = @form.discount
    return unless discount
    @order.discount_code = discount.code
    @order.discount_amount = DiscountCalculator.new(discount).apply(@order.subtotal)
  end

  def compute_tax_and_shipping
    calculator = OrderTotalsCalculator.new(@order, @form.shipping_address)
    calculator.compute!
  end

  def charge_payment
    result = PaymentService.charge(
      order: @order,
      payment_method: @form.payment_method
    )
    raise result.error_message unless result.success?
  end

  def decrement_inventory
    @order.line_items.each do |item|
      InventoryService.decrement(item.product, item.quantity)
    end
  end

  def clear_cart
    @form.cart.line_items.destroy_all
  end

  def track_discount_usage
    return unless @order.discount_code.present?
    DiscountCode.find_by(code: @order.discount_code).increment!(:times_used)
  end

  def send_emails
    OrderMailer.confirmation_email(@order).deliver_later
    OrderMailer.warehouse_notification(@order).deliver_later if @order.total > 500
  end

  def track_analytics
    AnalyticsService.track_order_placed(@order)
  end

  def discount_valid?
    return true if @form.discount_code.blank?
    discount = @form.discount
    return false unless discount
    return false if discount.expired?
    return false if discount.usage_limit_reached?
    true
  end

  def success(order)
    Result.new(success?: true, order: order)
  end

  def failure(message)
    Result.new(success?: false, error_message: message)
  end
end

class OrderCancellationService
  Result = Struct.new(:success?, :error_message, keyword_init: true)

  def self.call(order:, user:)
    new(order, user).call
  end

  def initialize(order, user)
    @order = order
    @user = user
  end

  def call
    return failure('Order cannot be cancelled in its current state.') unless cancellable?

    ActiveRecord::Base.transaction do
      @order.update!(status: 'cancelled', cancelled_at: Time.current)
      InventoryService.restock_order(@order)
      refund_if_paid
      OrderMailer.cancellation_email(@order).deliver_later
      AnalyticsService.track_order_cancelled(@order, @user)
    end
    success
  rescue ActiveRecord::RecordInvalid => e
    failure(e.record.errors.full_messages.to_sentence)
  rescue StandardError => e
    failure(e.message)
  end

  private

  def cancellable?
    %w[pending processing paid].include?(@order.status)
  end

  def refund_if_paid
    return unless @order.payment&.status == 'captured'
    result = PaymentService.refund(order: @order)
    raise result.error_message unless result.success?
  end

  def success
    Result.new(success?: true)
  end

  def failure(message)
    Result.new(success?: false, error_message: message)
  end
end

class OrderRefundService
  Result = Struct.new(:success?, :error_message, keyword_init: true)

  def self.call(order:, user:)
    new(order, user).call
  end

  def initialize(order, user)
    @order = order
    @user = user
  end

  def call
    return failure('Order is not eligible for refund.') unless refundable?

    ActiveRecord::Base.transaction do
      result = PaymentService.refund(order: @order)
      raise result.error_message unless result.success?
      @order.update!(status: 'refunded', refunded_at: Time.current)
      InventoryService.restock_order(@order)
      OrderMailer.refund_email(@order).deliver_later
      AnalyticsService.track_order_refunded(@order, @user)
    end
    success
  rescue ActiveRecord::RecordInvalid => e
    failure(e.record.errors.full_messages.to_sentence)
  rescue StandardError => e
    failure(e.message)
  end

  private

  def refundable?
    @order.status == 'paid' && @order.created_at > 30.days.ago
  end

  def success
    Result.new(success?: true)
  end

  def failure(message)
    Result.new(success?: false, error_message: message)
  end
end

class OrderUpdateService
  Result = Struct.new(:success?, :error_message, keyword_init: true)

  def self.call(order:, params:)
    new(order, params).call
  end

  def initialize(order, params)
    @order = order
    @params = params
  end

  def call
    return failure('Cannot update a processed order.') unless @order.status == 'pending'
    if @order.update(@params)
      success
    else
      failure(@order.errors.full_messages.to_sentence)
    end
  end

  private

  def success
    Result.new(success?: true)
  end

  def failure(message)
    Result.new(success?: false, error_message: message)
  end
end

class OrderDeletionService
  Result = Struct.new(:success?, :error_message, keyword_init: true)

  def self.call(order:)
    new(order).call
  end

  def initialize(order)
    @order = order
  end

  def call
    return failure('Cannot delete a processed order.') unless @order.status == 'pending'
    @order.destroy
    success
  end

  private

  def success
    Result.new(success?: true)
  end

  def failure(message)
    Result.new(success?: false, error_message: message)
  end
end

class ReorderService
  Result = Struct.new(:success?, :error_message, keyword_init: true)

  def self.call(order:, user:)
    new(order, user).call
  end

  def initialize(order, user)
    @order = order
    @user = user
  end

  def call
    return failure('Not authorized.') unless @order.user_id == @user.id
    cart = @user.cart
    ActiveRecord::Base.transaction do
      @order.line_items.each do |item|
        next if item.product.inventory_count < item.quantity
        add_to_cart(cart, item)
      end
    end
    success
  rescue StandardError => e
    failure(e.message)
  end

  private

  def add_to_cart(cart, item)
    line_item = cart.line_items.find_or_initialize_by(product_id: item.product_id)
    line_item.quantity = (line_item.quantity || 0) + item.quantity
    line_item.save!
  end

  def success
    Result.new(success?: true)
  end

  def failure(message)
    Result.new(success?: false, error_message: message)
  end
end

# =====================================================================
# Query objects
# =====================================================================

module OrderQueries
  class Index
    Result = Struct.new(:orders, :total_spent, :pending_count, keyword_init: true)

    def self.call(user:, params:)
      new(user, params).call
    end

    def initialize(user, params)
      @user = user
      @params = params
    end

    def call
      orders = @user.orders.order(created_at: :desc)
      Result.new(
        orders: orders,
        total_spent: orders.where(status: %w[paid shipped delivered]).sum(:total),
        pending_count: orders.where(status: %w[pending processing]).count
      )
    end
  end

  module ForUser
    def self.find(user, id)
      user.orders.find_by(id: id)
    end

    def self.all(user)
      user.orders.order(created_at: :desc)
    end
  end
end

# =====================================================================
# Helper objects
# =====================================================================

class DiscountCalculator
  def initialize(discount)
    @discount = discount
  end

  def apply(subtotal)
    case @discount.kind
    when 'percent' then (subtotal * @discount.value / 100).round(2)
    when 'fixed' then [@discount.value, subtotal].min
    else 0
    end
  end
end

class OrderTotalsCalculator
  def initialize(order, shipping_address)
    @order = order
    @shipping_address = shipping_address
  end

  def compute!
    @order.shipping_address = @shipping_address
    @order.billing_address = @shipping_address # assume same for now
    @order.tax_amount = (@order.subtotal - @order.discount_amount) * tax_rate
    @order.shipping_amount = compute_shipping
    @order.total = @order.subtotal - @order.discount_amount +
                   @order.tax_amount + @order.shipping_amount
  end

  private

  def tax_rate
    TAX_RATES.fetch(@shipping_address.state, 0.05)
  end

  def compute_shipping
    subtotal = @order.subtotal - @order.discount_amount
    return 0 if subtotal > 250
    base = @shipping_address.country == 'US' ? 9.99 : 29.99
    base + (subtotal > 100 ? 0 : 5)
  end

  TAX_RATES = {
    'CA' => 0.0875, 'NY' => 0.08, 'TX' => 0.0625, 'FL' => 0.06,
    'WA' => 0.065, 'OR' => 0.0, 'MT' => 0.0, 'NH' => 0.0, 'DE' => 0.0
  }.freeze
end

class InventoryService
  def self.decrement(product, quantity)
    raise "Insufficient stock for #{product.name}" if product.inventory_count < quantity
    product.update!(inventory_count: product.inventory_count - quantity)
  end

  def self.restock_order(order)
    order.line_items.each do |item|
      item.product.update!(inventory_count: item.product.inventory_count + item.quantity)
    end
  end
end

class PaymentService
  Result = Struct.new(:success?, :error_message, :transaction_id, keyword_init: true)

  def self.charge(order:, payment_method:)
    gateway = PaymentGateway.new(ENV['PAYMENT_GATEWAY_API_KEY'])
    result = gateway.charge(
      amount: (order.total * 100).to_i,
      currency: 'usd',
      payment_method_token: payment_method.token,
      description: "Order #{order.id}"
    )
    if result.success?
      Payment.create!(
        order_id: order.id, amount: order.total, currency: 'usd',
        gateway: gateway.name, gateway_transaction_id: result.transaction_id,
        status: 'captured'
      )
      order.update!(status: 'paid', paid_at: Time.current)
      Result.new(success?: true)
    else
      order.update!(status: 'failed')
      Result.new(success?: false, error_message: "Payment failed: #{result.error_message}")
    end
  rescue StandardError => e
    Result.new(success?: false, error_message: e.message)
  end

  def self.refund(order:)
    gateway = PaymentGateway.new(ENV['PAYMENT_GATEWAY_API_KEY'])
    result = gateway.refund(
      transaction_id: order.payment.gateway_transaction_id,
      amount: (order.total * 100).to_i
    )
    if result.success?
      order.payment.update!(status: 'refunded', refunded_at: Time.current)
      Result.new(success?: true)
    else
      Result.new(success?: false, error_message: "Refund failed: #{result.error_message}")
    end
  rescue StandardError => e
    Result.new(success?: false, error_message: e.message)
  end
end

class AnalyticsService
  def self.track_order_placed(order)
    track(order.user_id, 'Order Completed', order_id: order.id, total: order.total,
          item_count: order.line_items.sum(:quantity), discount_code: order.discount_code)
  end

  def self.track_order_cancelled(order, user)
    track(user.id, 'Order Cancelled', order_id: order.id, total: order.total)
  end

  def self.track_order_refunded(order, user)
    track(user.id, 'Order Refunded', order_id: order.id, total: order.total)
  end

  def self.track(user_id, event, properties)
    Analytics.track(user_id: user_id, event: event, properties: properties)
  end
end

# =====================================================================
# Serializers / presenters / exporters
# =====================================================================

class OrderSerializer
  def initialize(order)
    @order = order
  end

  def as_json
    {
      id: @order.id, status: @order.status, total: @order.total,
      subtotal: @order.subtotal, discount_amount: @order.discount_amount,
      tax_amount: @order.tax_amount, shipping_amount: @order.shipping_amount,
      created_at: @order.created_at,
      line_items: @order.line_items.map { |li| line_item_json(li) },
      shipping_address: address_json(@order.shipping_address),
      billing_address: address_json(@order.billing_address)
    }
  end

  private

  def line_item_json(li)
    { product_id: li.product_id, quantity: li.quantity,
      unit_price: li.unit_price, total_price: li.total_price }
  end

  def address_json(addr)
    return nil unless addr
    { line1: addr.line1, line2: addr.line2, city: addr.city, state: addr.state,
      postal_code: addr.postal_code, country: addr.country }
  end
end

class OrderPresenter
  def initialize(order)
    @order = order
  end

  def line_items
    @order.line_items.includes(:product)
  end

  def timeline
    events = []
    events << { timestamp: @order.created_at, event: 'Order placed' }
    events << { timestamp: @order.paid_at, event: 'Payment received' } if @order.paid_at
    events << { timestamp: @order.shipped_at, event: 'Shipped' } if @order.shipped_at
    events << { timestamp: @order.delivered_at, event: 'Delivered' } if @order.delivered_at
    events << { timestamp: @order.cancelled_at, event: 'Cancelled' } if @order.cancelled_at
    events << { timestamp: @order.refunded_at, event: 'Refunded' } if @order.refunded_at
    events.sort_by { |e| e[:timestamp] }
  end

  def can_cancel?
    %w[pending processing paid].include?(@order.status)
  end

  def can_refund?
    @order.status == 'paid' && @order.created_at > 30.days.ago
  end
end

class OrderCsvExporter
  HEADERS = %w[id status subtotal discount tax shipping total created_at item_count].freeze

  def self.call(orders)
    new(orders).call
  end

  def initialize(orders)
    @orders = orders
  end

  def call
    CSV.generate(headers: true) do |csv|
      csv << HEADERS
      @orders.each { |o| csv << row_for(o) }
    end
  end

  private

  def row_for(o)
    [o.id, o.status, o.subtotal, o.discount_amount, o.tax_amount,
     o.shipping_amount, o.total, o.created_at, o.line_items.sum(:quantity)]
  end
end

class OrderAnalyticsReport
  def initialize(user:, start_date:, end_date:)
    @user = user
    @start_date = start_date
    @end_date = end_date
  end

  def build
    orders = @user.orders.where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
    paid_orders = orders.where(status: %w[paid shipped delivered])
    {
      total_revenue: paid_orders.sum(:total),
      order_count: orders.count,
      average_order_value: average_order_value(paid_orders),
      refund_count: orders.where(status: 'refunded').count,
      refund_total: orders.where(status: 'refunded').sum(:total),
      cancellation_count: orders.where(status: 'cancelled').count,
      revenue_by_day: paid_orders.group_by_day(:created_at).sum(:total),
      top_products: top_products(orders),
      status_breakdown: orders.group(:status).count
    }
  end

  private

  def average_order_value(paid_orders)
    count = paid_orders.count
    count.positive? ? paid_orders.sum(:total) / count : 0
  end

  def top_products(orders)
    orders.joins(:line_items)
          .group('line_items.product_id')
          .order('sum_quantity DESC')
          .limit(10)
          .sum('line_items.quantity')
  end
end
