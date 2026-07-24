module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?, :current_user
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session.present?
    end

    def current_user
      Current.user
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      return Current.session if Current.session.present?

      session = find_session_by_cookie
      return clear_session_cookie! unless session
      return clear_session_cookie! if session.inactive? || !session.user.active_for_authentication?

      session.touch_last_seen_if_stale!
      Current.session = session
    end

    def find_session_by_cookie
      session_id = cookies.signed[:session_id]
      Session.find_by(id: session_id) if session_id
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to authentication_redirect_path
    end

    def after_authentication_url
      url = session.delete(:return_to_after_authenticating)
      return default_after_authentication_url unless url

      uri = URI.parse(url)
      (uri.host.nil? || uri.host == request.host) ? url : default_after_authentication_url
    rescue URI::InvalidURIError
      default_after_authentication_url
    end

    def authentication_redirect_path
      admin_controller? ? new_session_path : new_public_session_path
    end

    def default_after_authentication_url
      admin_controller? ? admin_root_url : root_url
    end

    def admin_controller?
      controller_path.start_with?("admin/")
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip, last_seen_at: Time.current).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = {
          value: session.id,
          httponly: true,
          same_site: :lax,
          secure: Rails.env.production?
        }
      end
    end

    def terminate_session
      Current.session&.destroy
      Current.session = nil
      cookies.delete(:session_id)
    end

    def clear_session_cookie!
      Current.session&.destroy
      Current.session = nil
      cookies.delete(:session_id)
      nil
    end
end
