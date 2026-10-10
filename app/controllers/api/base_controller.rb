module Api
  class BaseController < ActionController::API
    before_action :prevent_caching
    before_action :authenticate_key
    rate_limit to: 120, within: 1.minute, by: -> { @api_key.user_id }, scope: "resident-api", name: "owner",
      with: -> { render_rate_limit }
    after_action :prevent_caching

    rescue_from ActiveRecord::RecordNotFound, with: -> { render_error("not_found", "Content not found.", :not_found) }
    rescue_from ArgumentError, with: ->(error) { render_error("invalid_request", error.message, :unprocessable_entity) }

    private

      def authenticate_key
        scheme, credential = request.headers["Authorization"].to_s.split(" ", 2)
        @api_key = ApiAccessToken.authenticate(credential) if scheme&.casecmp?("Bearer")
        return if @api_key

        rate_limiting(to: 30, within: 1.minute, by: -> { request.remote_ip },
          with: -> { render_rate_limit }, store: self.class.cache_store, name: "invalid", scope: "resident-api")
        return if performed?

        response.headers["WWW-Authenticate"] = "Bearer"
        render_error("unauthorized", "A valid API key is required.", :unauthorized)
      end

      def prevent_caching
        response.headers["Cache-Control"] = "private, no-store"
        response.headers["Vary"] = "Authorization"
        response.headers.delete("ETag")
        response.headers.delete("Last-Modified")
      end

      def render_rate_limit
        response.headers["Retry-After"] = "60"
        render_error("rate_limited", "Too many requests. Retry in one minute.", :too_many_requests)
      end

      def render_error(code, message, status)
        render json: { error: { code: code, message: message } }, status: status
      end

      def serializer
        @serializer ||= Api::V1::Serializer.new(base_url: request.base_url)
      end

      def render_data(data, links: {})
        render json: { data: data, links: { self: request.original_url }.merge(links) }
      end

      def render_collection(records, preload: nil, &block)
        limit = integer_parameter(:limit, default: 50, maximum: 100)
        offset = integer_parameter(:offset, default: 0, minimum: 0)
        count = records.size
        page = if records.is_a?(Array)
          records.slice(offset, limit) || []
        else
          records.limit(limit).offset(offset).to_a
        end
        if preload
          page.each { |record| preload.each { |association| record.association(association).reset } }
          ActiveRecord::Associations::Preloader.new(records: page, associations: preload).call
        end
        serializer.preload_illustrations(page)
        serializer.content_updates.preload(page) if page.first.is_a?(Meeting) || page.first.is_a?(Topic)
        query = request.query_parameters.slice(*Api::Handbook::FILTER_NAMES)
        next_url = if offset + page.size < count
          "#{request.base_url}#{request.path}?#{query.merge('offset' => offset + page.size, 'limit' => limit).to_query}"
        end
        render json: { data: page.map(&block), pagination: { offset: offset, limit: limit,
          returned_count: page.size, total_count: count }, links: { self: request.original_url, next: next_url } }
      end

      def integer_parameter(name, default:, minimum: 1, maximum: nil)
        raw = params[name]
        return default if raw.nil?
        raise ArgumentError, "#{name} must be an integer." unless raw.to_s.match?(/\A\d+\z/)

        value = Integer(raw.to_s, 10)
        if value < minimum || (maximum && value > maximum)
          raise ArgumentError, "#{name} is outside the supported range."
        end
        value
      end

      def search_query
        value = params[:q]
        return if value.blank?
        raise ArgumentError, "q must be text of at most 200 characters." unless value.is_a?(String) && value.length <= 200

        value
      end

      def update_filters(default_sort:)
        since = params[:updated_since]
        if since
          unless since.is_a?(String) && since.match?(/(?:Z|[+-]\d{2}:\d{2})\z/)
            raise ArgumentError, "updated_since must be an ISO 8601 timestamp with a timezone."
          end
          since = Time.iso8601(since)
        end
        sort = params[:sort] || (since ? "updated" : default_sort)
        raise ArgumentError, "sort must be #{default_sort} or updated." unless [ default_sort, "updated" ].include?(sort)

        [ since, sort ]
      end

      def filter_updated_records(records, since:)
        return records unless since

        serializer.content_updates.preload(records.to_a)
        records.select { |record| serializer.content_updates.for(record)[:updated_at] >= since }
      end

      def updated_records(records)
        serializer.content_updates.preload(records)
        records.sort_by { |record| [ -serializer.content_updates.for(record)[:updated_at].to_r, -record.id ] }
      end
  end
end
