module ApplicationCable
  class Connection < ActionCable::Connection::Base
    def connect
      # Public site: allow unauthenticated connections.
      # Admin authentication is handled via HTTP session cookies.
    end
  end
end
