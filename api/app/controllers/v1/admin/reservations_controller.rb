# frozen_string_literal: true

module V1
  module Admin
    # 予約の一覧・詳細・キャンセル・日時変更。
    class ReservationsController < BaseController
      DEFAULT_PER_PAGE = 50
      MAX_PER_PAGE = 200

      before_action :load_reservation, only: %i[show cancel reschedule]

      def index
        scope = Reservation.includes(:booking_type).order(start_at: :desc)
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.joins(:booking_type).where(booking_types: { slug: params[:slug] }) if params[:slug].present?
        scope = scope.where(start_at: from_param..) if from_param
        scope = scope.where(start_at: ..to_param) if to_param

        render json: {
          reservations: scope.limit(per_page).offset(offset).map { |r| ReservationSerializer.admin_payload(r) },
          total: scope.count,
          limit: per_page,
          offset: offset
        }
      end

      def show
        render json: ReservationSerializer.admin_payload(@reservation)
      end

      def cancel
        result = Reservations::Canceller.new(reservation: @reservation).call

        return render_service_failure(result) if result.failure?

        render json: ReservationSerializer.admin_payload(result.value)
      end

      def reschedule
        result = Reservations::Rescheduler.new(reservation: @reservation, start_at: params[:startAt]).call

        return render_service_failure(result) if result.failure?

        render json: ReservationSerializer.admin_payload(result.value)
      end

      private

      def load_reservation
        @reservation = Reservation.find(params[:id])
      end

      def per_page
        [[params.fetch(:limit, DEFAULT_PER_PAGE).to_i, 1].max, MAX_PER_PAGE].min
      end

      def offset
        [params.fetch(:offset, 0).to_i, 0].max
      end

      def from_param
        parse_time(params[:from])
      end

      def to_param
        parse_time(params[:to])
      end

      def parse_time(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
