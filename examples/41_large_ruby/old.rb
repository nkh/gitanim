# frozen_string_literal: true

# Legacy OrdersController — a "fat controller" with all business logic
# inlined. Renders views, sends emails, charges cards, updates inventory,
# and computes analytics all in the same file.

class OrdersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_order, only: %i[show edit update destroy cancel refund invoice]

  # GET /orders
  def index
    @orders = Order.where(user_id: current_user.id).order(created_at: :desc)
    @total_spent = @orders.where(status: %w[paid shipped delivered]).sum(:total)
    @pending_count = @orders.where(status: %w[pending processing]).count

    respond_to do |format|
      format.html
      format.json { render json: @orders }
      format.csv do
        csv_data = generate_csv(@orders)
        send_data csv_data, filename: "orders-#{Date.today}.csv", type: 'text/csv'
      end
    end
  end

  # GET /orders/:id
  def show
    @line_items = @order.line_items.includes(:product)
    @shipping_address = @order.shipping_address
    @billing_address = @order.billing_address
    @payment = @order.payment
    @timeline = build_timeline(@order)
    @can_cancel = @order.status == 'pending' || @order.status == 'processing'
    @can_refund = @order.status == 'paid' && @order.created_at > 30.days.ago

    respond_to do |format|
      format.html
      format.json { render json: order_json(@order) }
    end
  end

  # GET /orders/new
  def new
    @order = Order.new
    @cart = current_user.cart
    @addresses = current_user.addresses
    @payment_methods = current_user.payment_methods.active
  end

  # POST /orders
  def create
    @order = Order.new(order_params.merge(user_id: current_user.id))
    @cart = current_user.cart
    @addresses = current_user.addresses
    @payment_methods = current_user.payment_methods.active

    if @cart.line_items.empty?
      flash.now[:error] = 'Your cart is empty.'
      render :new, status: :unprocessable_entity and return
    end

    @order.status = 'pending'
    @order.subtotal = 0
    @cart.line_items.each do |item|
      @order.line_items.build(
        product_id: item.product_id,
        quantity: item.quantity,
        unit_price: item.product.price,
        total_price: item.product.price * item.quantity
      )
      @order.subtotal += item.product.price * item.quantity
    end

    # Apply discount code if provided.
    if params[:discount_code].present?
      discount = DiscountCode.find_by(code: params[:discount_code].upcase)
      if discount.nil?
        @order.errors.add(:base, 'Invalid discount code')
        render :new, status: :unprocessable_entity and return
      end
      if discount.expired?
        @order.errors.add(:base, 'Discount code has expired')
        render :new, status: :unprocessable_entity and return
      end
      if discount.usage_limit_reached?
        @order.errors.add(:base, 'Discount code usage limit reached')
        render :new, status: :unprocessable_entity and return
      end
      @order.discount_code = discount.code
      @order.discount_amount = case discount.kind
                                when 'percent' then (@order.subtotal * discount.value / 100).round(2)
                                when 'fixed' then [discount.value, @order.subtotal].min
                                else 0
                                end
    end

    # Compute tax.
    shipping_address = current_user.addresses.find_by(id: params[:shipping_address_id])
    if shipping_address.nil?
      @order.errors.add(:base, 'Shipping address is required')
      render :new, status: :unprocessable_entity and return
    end
    @order.shipping_address = shipping_address
    @order.tax_amount = (@order.subtotal - @order.discount_amount) * tax_rate_for(shipping_address.state)

    # Compute shipping.
    @order.shipping_amount = compute_shipping(@order.subtotal - @order.discount_amount,
                                              shipping_address.country)
    @order.total = @order.subtotal - @order.discount_amount + @order.tax_amount + @order.shipping_amount

    # Validate billing address.
    billing_address = current_user.addresses.find_by(id: params[:billing_address_id])
    if billing_address.nil?
      @order.errors.add(:base, 'Billing address is required')
      render :new, status: :unprocessable_entity and return
    end
    @order.billing_address = billing_address

    # Validate payment method.
    payment_method = current_user.payment_methods.find_by(id: params[:payment_method_id])
    if payment_method.nil? || !payment_method.active?
      @order.errors.add(:base, 'Valid payment method is required')
      render :new, status: :unprocessable_entity and return
    end

    ActiveRecord::Base.transaction do
      @order.save!
      # Charge the card via the payment gateway.
      gateway = PaymentGateway.new(ENV['PAYMENT_GATEWAY_API_KEY'])
      result = gateway.charge(
        amount: (@order.total * 100).to_i,
        currency: 'usd',
        payment_method_token: payment_method.token,
        description: "Order #{@order.id}"
      )
      if result.success?
        @order.payment = Payment.create!(
          order_id: @order.id,
          amount: @order.total,
          currency: 'usd',
          gateway: gateway.name,
          gateway_transaction_id: result.transaction_id,
          status: 'captured'
        )
        @order.update!(status: 'paid', paid_at: Time.current)
      else
        @order.update!(status: 'failed')
        @order.errors.add(:base, "Payment failed: #{result.error_message}")
        raise ActiveRecord::Rollback
      end

      # Decrement inventory.
      @order.line_items.each do |item|
        product = item.product
        if product.inventory_count < item.quantity
          @order.errors.add(:base, "Insufficient stock for #{product.name}")
          raise ActiveRecord::Rollback
        end
        product.update!(inventory_count: product.inventory_count - item.quantity)
      end

      # Clear the cart.
      @cart.line_items.destroy_all

      # Increment discount code usage.
      if @order.discount_code.present?
        DiscountCode.find_by(code: @order.discount_code).increment!(:times_used)
      end

      # Send confirmation email.
      OrderMailer.confirmation_email(@order).deliver_later
      OrderMailer.warehouse_notification(@order).deliver_later if @order.total > 500

      # Track analytics.
      Analytics.track(
        user_id: current_user.id,
        event: 'Order Completed',
        properties: {
          order_id: @order.id,
          total: @order.total,
          item_count: @order.line_items.sum(:quantity),
          discount_code: @order.discount_code
        }
      )
    end

    redirect_to @order, notice: 'Order placed successfully.'
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:error] = e.record.errors.full_messages.to_sentence
    render :new, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("Order creation failed: #{e.class}: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
    flash.now[:error] = 'An unexpected error occurred. Please try again.'
    render :new, status: :internal_server_error
  end

  # PATCH/PUT /orders/:id
  def update
    if @order.status != 'pending'
      redirect_to @order, alert: 'Cannot update a processed order.' and return
    end

    if @order.update(order_params)
      redirect_to @order, notice: 'Order updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /orders/:id
  def destroy
    if @order.status == 'pending'
      @order.destroy
      redirect_to orders_path, notice: 'Order deleted.'
    else
      redirect_to @order, alert: 'Cannot delete a processed order.'
    end
  end

  # POST /orders/:id/cancel
  def cancel
    unless %w[pending processing paid].include?(@order.status)
      redirect_to @order, alert: 'Order cannot be cancelled in its current state.' and return
    end

    ActiveRecord::Base.transaction do
      @order.update!(status: 'cancelled', cancelled_at: Time.current)

      # Restock inventory.
      @order.line_items.each do |item|
        item.product.update!(inventory_count: item.product.inventory_count + item.quantity)
      end

      # Refund if already paid.
      if @order.payment&.status == 'captured'
        gateway = PaymentGateway.new(ENV['PAYMENT_GATEWAY_API_KEY'])
        refund_result = gateway.refund(
          transaction_id: @order.payment.gateway_transaction_id,
          amount: (@order.total * 100).to_i
        )
        if refund_result.success?
          @order.payment.update!(status: 'refunded', refunded_at: Time.current)
        else
          @order.errors.add(:base, "Refund failed: #{refund_result.error_message}")
          raise ActiveRecord::Rollback
        end
      end

      OrderMailer.cancellation_email(@order).deliver_later
      Analytics.track(user_id: current_user.id, event: 'Order Cancelled',
                      properties: { order_id: @order.id, total: @order.total })
    end

    redirect_to @order, notice: 'Order cancelled.'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @order, alert: e.record.errors.full_messages.to_sentence
  end

  # POST /orders/:id/refund
  def refund
    unless @order.status == 'paid' && @order.created_at > 30.days.ago
      redirect_to @order, alert: 'Order is not eligible for refund.' and return
    end

    ActiveRecord::Base.transaction do
      gateway = PaymentGateway.new(ENV['PAYMENT_GATEWAY_API_KEY'])
      result = gateway.refund(
        transaction_id: @order.payment.gateway_transaction_id,
        amount: (@order.total * 100).to_i
      )
      if result.success?
        @order.payment.update!(status: 'refunded', refunded_at: Time.current)
        @order.update!(status: 'refunded', refunded_at: Time.current)

        @order.line_items.each do |item|
          item.product.update!(inventory_count: item.product.inventory_count + item.quantity)
        end

        OrderMailer.refund_email(@order).deliver_later
        Analytics.track(user_id: current_user.id, event: 'Order Refunded',
                        properties: { order_id: @order.id, total: @order.total })
      else
        @order.errors.add(:base, "Refund failed: #{result.error_message}")
        raise ActiveRecord::Rollback
      end
    end

    redirect_to @order, notice: 'Order refunded.'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @order, alert: e.record.errors.full_messages.to_sentence
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
    original = Order.find(params[:id])
    if original.user_id != current_user.id
      redirect_to orders_path, alert: 'Not authorized.' and return
    end

    cart = current_user.cart
    ActiveRecord::Base.transaction do
      original.line_items.each do |item|
        if item.product.inventory_count >= item.quantity
          cart.line_items.find_or_initialize_by(product_id: item.product_id) do |li|
            li.quantity = (li.quantity || 0) + item.quantity
          end.save!
        end
      end
    end

    redirect_to cart_path, notice: 'Items added to cart.'
  end

  # GET /orders/analytics
  def analytics
    @start_date = Date.parse(params[:start_date] || 30.days.ago.to_date.to_s)
    @end_date = Date.parse(params[:end_date] || Date.today.to_s)

    orders = Order.where(user_id: current_user.id)
                  .where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)

    @total_revenue = orders.where(status: %w[paid shipped delivered]).sum(:total)
    @order_count = orders.count
    @average_order_value = @order_count.positive? ? @total_revenue / @order_count : 0
    @refund_count = orders.where(status: 'refunded').count
    @refund_total = orders.where(status: 'refunded').sum(:total)
    @cancellation_count = orders.where(status: 'cancelled').count

    @revenue_by_day = orders.where(status: %w[paid shipped delivered])
                            .group_by_day(:created_at)
                            .sum(:total)

    @top_products = orders.joins(:line_items)
                          .group('line_items.product_id')
                          .order('sum_quantity DESC')
                          .limit(10)
                          .sum('line_items.quantity')

    @status_breakdown = orders.group(:status).count

    respond_to do |format|
      format.html
      format.json { render json: {
        total_revenue: @total_revenue,
        order_count: @order_count,
        average_order_value: @average_order_value,
        refund_count: @refund_count,
        refund_total: @refund_total,
        cancellation_count: @cancellation_count,
        revenue_by_day: @revenue_by_day,
        top_products: @top_products,
        status_breakdown: @status_breakdown
      } }
    end
  end

  # GET /orders/export
  def export
    orders = Order.where(user_id: current_user.id).order(created_at: :desc)
    csv_data = generate_csv(orders)
    send_data csv_data, filename: "orders-#{Date.today}.csv", type: 'text/csv'
  end

  # GET /orders/track/:id
  def track
    @order = Order.find_by(id: params[:id])
    if @order.nil? || @order.user_id != current_user.id
      redirect_to orders_path, alert: 'Order not found.' and return
    end

    if @order.tracking_number.blank?
      redirect_to @order, alert: 'Tracking information is not yet available.' and return
    end

    carrier = detect_carrier(@order.tracking_number)
    if carrier.nil?
      redirect_to @order, alert: 'Unable to detect carrier.' and return
    end

    begin
      tracker = ShipmentTracker.new(ENV['SHIPMENT_API_KEY'])
      @tracking_info = tracker.track(carrier: carrier, number: @order.tracking_number)
      @tracking_events = @tracking_info.events.sort_by { |e| e[:timestamp] }
    rescue StandardError => e
      Rails.logger.error("Tracking failed: #{e.message}")
      @tracking_error = "Unable to retrieve tracking information: #{e.message}"
    end

    respond_to do |format|
      format.html
      format.json { render json: { tracking: @tracking_info, error: @tracking_error } }
    end
  end

  # POST /orders/:id/mark_shipped
  def mark_shipped
    @order = Order.find_by(id: params[:id])
    if @order.nil? || @order.user_id != current_user.id
      redirect_to orders_path, alert: 'Order not found.' and return
    end
    unless @order.status == 'paid'
      redirect_to @order, alert: 'Only paid orders can be marked as shipped.' and return
    end

    tracking_number = params[:tracking_number].to_s.strip
    carrier = params[:carrier].to_s.strip
    if tracking_number.blank?
      redirect_to @order, alert: 'Tracking number is required.' and return
    end
    carrier = detect_carrier(tracking_number) if carrier.blank?
    if carrier.nil?
      redirect_to @order, alert: 'Unable to detect carrier; please specify.' and return
    end

    ActiveRecord::Base.transaction do
      @order.update!(status: 'shipped', shipped_at: Time.current,
                     tracking_number: tracking_number, carrier: carrier)
      OrderMailer.shipped_email(@order).deliver_later
      Analytics.track(user_id: current_user.id, event: 'Order Shipped',
                      properties: { order_id: @order.id, carrier: carrier })
    end
    redirect_to @order, notice: 'Order marked as shipped.'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @order, alert: e.record.errors.full_messages.to_sentence
  end

  # POST /orders/:id/mark_delivered
  def mark_delivered
    @order = Order.find_by(id: params[:id])
    if @order.nil? || @order.user_id != current_user.id
      redirect_to orders_path, alert: 'Order not found.' and return
    end
    unless @order.status == 'shipped'
      redirect_to @order, alert: 'Only shipped orders can be marked as delivered.' and return
    end

    ActiveRecord::Base.transaction do
      @order.update!(status: 'delivered', delivered_at: Time.current)
      OrderMailer.delivered_email(@order).deliver_later
      Analytics.track(user_id: current_user.id, event: 'Order Delivered',
                      properties: { order_id: @order.id })
      # Schedule a review reminder.
      ReviewReminderJob.set(wait: 7.days).perform_later(@order.id)
    end
    redirect_to @order, notice: 'Order marked as delivered.'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @order, alert: e.record.errors.full_messages.to_sentence
  end

  # POST /orders/:id/return
  def request_return
    @order = Order.find_by(id: params[:id])
    if @order.nil? || @order.user_id != current_user.id
      redirect_to orders_path, alert: 'Order not found.' and return
    end
    unless @order.status == 'delivered' && @order.delivered_at > 14.days.ago
      redirect_to @order, alert: 'Order is not eligible for return.' and return
    end

    line_item_ids = params[:line_item_ids] || []
    reason = params[:reason].to_s.strip
    if line_item_ids.empty?
      redirect_to @order, alert: 'Select at least one item to return.' and return
    end
    if reason.blank?
      redirect_to @order, alert: 'A reason is required.' and return
    end

    ActiveRecord::Base.transaction do
      line_items = @order.line_items.where(id: line_item_ids)
      return_request = ReturnRequest.create!(
        order_id: @order.id,
        user_id: current_user.id,
        reason: reason,
        status: 'pending',
        total_refund: line_items.sum(:total_price)
      )
      line_items.each do |li|
        ReturnRequestLineItem.create!(
          return_request_id: return_request.id,
          line_item_id: li.id,
          quantity: li.quantity,
          refund_amount: li.total_price
        )
      end
      OrderMailer.return_request_email(@order, return_request).deliver_later
      Analytics.track(user_id: current_user.id, event: 'Return Requested',
                      properties: { order_id: @order.id,
                                    return_id: return_request.id,
                                    total_refund: return_request.total_refund })
    end
    redirect_to @order, notice: 'Return request submitted.'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @order, alert: e.record.errors.full_messages.to_sentence
  end

  # GET /orders/:id/returns
  def returns
    @order = Order.find_by(id: params[:id])
    if @order.nil? || @order.user_id != current_user.id
      redirect_to orders_path, alert: 'Order not found.' and return
    end
    @return_requests = @order.return_requests.order(created_at: :desc)
    respond_to do |format|
      format.html
      format.json { render json: @return_requests }
    end
  end

  # POST /orders/:id/review
  def submit_review
    @order = Order.find_by(id: params[:id])
    if @order.nil? || @order.user_id != current_user.id
      redirect_to orders_path, alert: 'Order not found.' and return
    end
    unless @order.status == 'delivered'
      redirect_to @order, alert: 'Only delivered orders can be reviewed.' and return
    end

    reviews = params[:reviews] || []
    if reviews.empty?
      redirect_to @order, alert: 'No reviews submitted.' and return
    end

    ActiveRecord::Base.transaction do
      reviews.each do |review_params|
        product = Product.find_by(id: review_params[:product_id])
        next unless product
        existing = Review.find_by(user_id: current_user.id, product_id: product.id,
                                  order_id: @order.id)
        if existing
          existing.update!(rating: review_params[:rating],
                           title: review_params[:title],
                           body: review_params[:body])
        else
          Review.create!(user_id: current_user.id, product_id: product.id,
                         order_id: @order.id, rating: review_params[:rating],
                         title: review_params[:title], body: review_params[:body])
        end
        # Recompute product rating.
        avg_rating = product.reviews.average(:rating).to_f.round(2)
        review_count = product.reviews.count
        product.update!(average_rating: avg_rating, review_count: review_count)
      end
      Analytics.track(user_id: current_user.id, event: 'Reviews Submitted',
                      properties: { order_id: @order.id, count: reviews.size })
    end
    redirect_to @order, notice: 'Thanks for your review!'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @order, alert: e.record.errors.full_messages.to_sentence
  end

  private

  def set_order
    @order = Order.find_by(id: params[:id])
    if @order.nil? || @order.user_id != current_user.id
      redirect_to orders_path, alert: 'Order not found.' and return
    end
  end

  def order_params
    params.require(:order).permit(:notes, :gift_wrap, :shipping_method,
                                  :shipping_address_id, :billing_address_id)
  end

  def generate_csv(orders)
    CSV.generate(headers: true) do |csv|
      csv << %w[id status subtotal discount tax shipping total created_at item_count]
      orders.each do |o|
        csv << [
          o.id, o.status, o.subtotal, o.discount_amount, o.tax_amount,
          o.shipping_amount, o.total, o.created_at, o.line_items.sum(:quantity)
        ]
      end
    end
  end

  def order_json(order)
    {
      id: order.id,
      status: order.status,
      total: order.total,
      subtotal: order.subtotal,
      discount_amount: order.discount_amount,
      tax_amount: order.tax_amount,
      shipping_amount: order.shipping_amount,
      created_at: order.created_at,
      line_items: order.line_items.map do |li|
        { product_id: li.product_id, quantity: li.quantity,
          unit_price: li.unit_price, total_price: li.total_price }
      end,
      shipping_address: address_json(order.shipping_address),
      billing_address: address_json(order.billing_address)
    }
  end

  def address_json(address)
    return nil unless address
    {
      line1: address.line1, line2: address.line2, city: address.city,
      state: address.state, postal_code: address.postal_code,
      country: address.country
    }
  end

  def build_timeline(order)
    events = []
    events << { timestamp: order.created_at, event: 'Order placed' }
    events << { timestamp: order.paid_at, event: 'Payment received' } if order.paid_at
    events << { timestamp: order.shipped_at, event: 'Shipped' } if order.shipped_at
    events << { timestamp: order.delivered_at, event: 'Delivered' } if order.delivered_at
    events << { timestamp: order.cancelled_at, event: 'Cancelled' } if order.cancelled_at
    events << { timestamp: order.refunded_at, event: 'Refunded' } if order.refunded_at
    events.sort_by { |e| e[:timestamp] }
  end

  def tax_rate_for(state)
    rates = {
      'CA' => 0.0875, 'NY' => 0.08, 'TX' => 0.0625, 'FL' => 0.06,
      'WA' => 0.065, 'OR' => 0.0, 'MT' => 0.0, 'NH' => 0.0, 'DE' => 0.0
    }
    rates[state] || 0.05
  end

  def compute_shipping(subtotal, country)
    return 0 if subtotal > 250
    base = country == 'US' ? 9.99 : 29.99
    base + (subtotal > 100 ? 0 : 5)
  end

  def detect_carrier(tracking_number)
    return 'ups' if tracking_number.match?(/^1Z[0-9A-Z]{16}$/i)
    return 'fedex' if tracking_number.match?(/^\d{15}$/)
    return 'usps' if tracking_number.match?(/^\d{20,22}$/)
    return 'dhl' if tracking_number.match?(/^\d{10}$/)
    nil
  end
end
