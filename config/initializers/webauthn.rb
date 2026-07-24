WebAuthn.configure do |config|
  config.allowed_origins = [ ENV.fetch("WEBAUTHN_ORIGIN", "http://localhost:3000") ]
  config.rp_id = ENV.fetch("WEBAUTHN_RP_ID", "localhost")
  config.rp_name = ENV.fetch("WEBAUTHN_RP_NAME", "Two Rivers Reporter")
end
