require 'ya2yaml'

module Translate
  class Engine < Rails::Engine
  end if defined?(Rails) && Rails::VERSION::MAJOR >= 3

  class << self
    # For configuring Google Translate API key
    attr_accessor :api_key
    # For configuring Bing Application id
    attr_accessor :app_id
  end
end

Dir[File.join(File.dirname(__FILE__), "translate", "*.rb")].each do |file|
  require file
end
