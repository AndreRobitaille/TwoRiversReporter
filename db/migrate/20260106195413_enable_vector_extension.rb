class EnableVectorExtension < ActiveRecord::Migration[8.1]
  def change
    # pgvector extension skipped in this environment.
    # To enable in production: enable_extension "vector"
  end
end
