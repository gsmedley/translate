class TranslateController < ActionController::Base
  # It seems users with active_record_store may get a "no :secret given" error if we don't disable csrf protection,
  skip_before_action :verify_authenticity_token, raise: false

  layout 'translate'

  before_action :init_translations
  before_action :set_locale

  # GET /translate
  def index
    params.permit!
    initialize_keys
    filter_by_key_pattern
    filter_by_text_pattern
    filter_by_translated_text_pattern
    filter_by_translated_or_changed
    sort_keys
    paginate_keys
    @total_entries = @keys.size
    @page_title = page_title
  end

  # POST /translate
  def translate
    params.permit!
    processed_parameters = process_array_parameters(params[:key])
    I18n.backend.store_translations(@to_locale, Translate::Keys.to_deep_hash(processed_parameters))
    Translate::Storage.new(@to_locale).write_to_file
    Translate::Log.new(@from_locale, @to_locale, params[:key].keys).write_to_file
    force_init_translations # Force reload from YAML file
    flash[:notice] = "Translations saved"
    old_params = params.slice(:filter, :sort_by, :key_type, :key_pattern, :text_type, :text_pattern, :translated_text_type, :translated_text_pattern)
    redirect_to( {:action => :index}.merge(old_params) )
  end

  # GET /translate/reload
  def reload
    params.permit!
    Translate::Keys.files = nil
    redirect_to :action => 'index'
  end

  def download
    params.permit!
    initialize_keys
    text = Translate::Storage.new(@to_locale).read_from_file
    send_data text, :filename => @to_locale.to_s + ".yml"
  
  end

  private
  def initialize_keys
    @files = Translate::Keys.files
    @keys = (@files.keys.map(&:to_s) + Translate::Keys.new.i18n_keys(@from_locale)).uniq
    @keys.reject! do |key|
      from_text = lookup(@from_locale, key)
      # When translating from one language to another, make sure there is a text to translate from.
      # The only supported formats are String and Array. We don't support other formats
      (@from_locale != @to_locale && !from_text.present?) || (from_text.present? && !from_text.is_a?(String) && !from_text.is_a?(Array))
    end
  end

  def page_title
    "Translate"
  end

  def lookup(locale, key)
    I18n.backend.send(:lookup, locale, key)
  end
  helper_method :lookup

  def from_locales
    # Attempt to get the list of locale from configuration
    from_loc = Rails.application.config.from_locales if Rails.application.config.respond_to?(:from_locales)
    return I18n.available_locales if from_loc.blank?
    raise StandardError, "from_locale expected to be an array" if from_loc.class != Array
    from_loc
  end
  helper_method :from_locales

  def to_locales
    to_loc = Rails.application.config.to_locales if Rails.application.config.respond_to?(:to_locales)
    return I18n.available_locales if to_loc.blank?
    raise StandardError, "to_locales expected to be an array" if to_loc.class != Array
    to_loc
  end
  helper_method :to_locales 

  def filter_by_translated_or_changed
    params[:filter] ||= 'all'
    return if params[:filter] == 'all'
    @keys.reject! do |key|
      case params[:filter]
      when 'untranslated'
        lookup(@to_locale, key).present?
      when 'translated'
        lookup(@to_locale, key).blank?
      when 'changed'
        lookup(@from_locale, key).to_s == lookup(@to_locale, key).to_s 
      when 'list_changed'
        fr = lookup(@from_locale, key).to_s.squish  
        to = lookup(@to_locale, key).to_s.squish 
        if fr.downcase != to.downcase
          p '--'
          p 'c:' + fr
          p 'g:' + to
        end
        fr.downcase == to.downcase
      else
        raise "Unknown filter '#{params[:filter]}'"
      end
    end
  end

  def filter_by_key_pattern
    return if params[:key_pattern].blank?
    @keys.reject! do |key|
      case params[:key_type]
      when "starts_with"
        !key.starts_with?(params[:key_pattern])
      when "contains"
        key.index(params[:key_pattern]).nil?
      else
        raise "Unknown key_type '#{params[:key_type]}'"
      end
    end
  end

  def filter_by_text_pattern
    return if params[:text_pattern].blank?
    @keys.reject! do |key|
      case params[:text_type]
      when 'contains'
        !lookup(@from_locale, key).present? || !lookup(@from_locale, key).to_s.downcase.index(params[:text_pattern].downcase)
      when 'equals'
        !lookup(@from_locale, key).present? || lookup(@from_locale, key).to_s.downcase != params[:text_pattern].downcase
      else
        raise "Unknown text_type '#{params[:text_type]}'"
      end
    end
  end

  def filter_by_translated_text_pattern
    return if params[:translated_text_pattern].blank?
    @keys.reject! do |key|
      case params[:translated_text_type]
      when 'contains' then
        !lookup(@to_locale, key).present? || !lookup(@to_locale, key).to_s.downcase.index(params[:translated_text_pattern].downcase)
      when 'equals' then
        !lookup(@to_locale, key).present? || lookup(@to_locale, key).to_s.downcase != params[:translated_text_pattern].downcase
      else
        raise "Unknown translated_text_type '#{params[:translated_text_type]}'"
      end
    end
  end

  def sort_keys
    params[:sort_by] ||= "key"
    case params[:sort_by]
    when "key"
      @keys.sort!
    when "text"
      @keys.sort! do |key1, key2|
        if lookup(@from_locale, key1).present? && lookup(@from_locale, key2).present?
          lookup(@from_locale, key1).to_s.downcase <=> lookup(@from_locale, key2).to_s.downcase
        elsif lookup(@from_locale, key1).present?
          -1
        else
          1
        end
      end
    else
      raise "Unknown sort_by '#{params[:sort_by]}'"
    end
  end

  def paginate_keys
    params[:page] ||= 1
    @paginated_keys = @keys[offset, per_page]
  end

  def offset
    (params[:page].to_i - 1) * per_page
  end

  def per_page
    50
  end
  helper_method :per_page

  def init_translations
    I18n.backend.send(:init_translations) unless I18n.backend.initialized?
  end

  def force_init_translations
    I18n.backend.send(:init_translations)
  end

  def default_locale
    I18n.default_locale
  end

  def default_to_locale
    :en
  end

  def set_locale
    session[:from_locale] ||= default_locale
    session[:to_locale] ||= default_to_locale
    session[:from_locale] = params[:from_locale] if params[:from_locale].present?
    session[:to_locale] = params[:to_locale] if params[:to_locale].present?
    @from_locale = session[:from_locale].to_sym
    @to_locale = session[:to_locale].to_sym
  end

  def process_array_parameters(parameter)
    reconstructed_hash = Hash.new

    parameter.each do |key, value|
      if value.is_a?(String)
        reconstructed_hash[key] = value
      elsif value.is_a?(Hash)
        reconstructed_hash[key] = Translate::Keys.arraylize(value)
      end
    end
    reconstructed_hash
  end
end
