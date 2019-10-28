Rails.application.routes.draw do
  get 'translate' => 'translate#index', :as => :translate_list
  post 'translate' => 'translate#translate', :as => :translate
  get 'translate/reload' => 'translate#reload', :as => :translate_reload
  get 'translate/download' => 'translate#download', :as => :translate_download
end
