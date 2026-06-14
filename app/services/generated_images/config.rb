module GeneratedImages
  class Config
    def self.enabled?
      ENV.fetch("GENERATED_IMAGES_ENABLED", "false") == "true"
    end
  end
end
