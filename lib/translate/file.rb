require 'fileutils'

class Translate::File
  attr_accessor :path
  
  def initialize(path)
    self.path = path
  end
  
  def write(keys)
    FileUtils.mkdir_p File.dirname(path)
    yml_keys = keys_to_yaml( Translate::File.deep_stringify_keys(keys) )
    File.open(path, "w") do |file| 
      file.write yml_keys
    end    
  end
  
  def read
    File.exists?(path) ? YAML::load(IO.read(path)) : {}
  end

  def read_raw
    File.exists?(path) ? File.read(path) : ""
  end

  # Stringifying keys for prettier YAML
  def self.deep_stringify_keys(hash)
    hash.inject({}) { |result, (key, value)|
      value = deep_stringify_keys(value) if value.is_a? Hash
      
      result[(key.to_s rescue key).present? ?  key.to_s : key] = value
      result
    }
  end
  
  private

  def keys_to_yaml(keys)

    yaml = YAML.dump(keys)
    
    ast = Psych.parse_stream yaml
    
    # First pass, quote everything
    ast.grep(Psych::Nodes::Scalar).each do |node|
      node.plain  = false
      node.quoted = true
      node.style  = Psych::Nodes::Scalar::DOUBLE_QUOTED
    end
    
    # Second pass, unquote keys, bools and ints
    ast.grep(Psych::Nodes::Mapping).each do |node|
      node.children.each_slice(2) do |k, v|
        k.plain  = true
        k.quoted = false
        k.style  = Psych::Nodes::Scalar::ANY


        if k.to_ruby.to_s == "false" || k.to_ruby.to_s == "true"
          k.plain  = false
          k.quoted = true
          k.style  = Psych::Nodes::Scalar::DOUBLE_QUOTED
        end
       
        if v.to_ruby.to_s == v.to_ruby.to_s.to_i.to_s || v.to_ruby.to_s == "true" || v.to_ruby.to_s == "false"
          v.plain  = true
          v.quoted = false
          v.style  = Psych::Nodes::Scalar::ANY
        end
        
      end
    end

    ast.yaml( nil, line_width: -1 )
  end
end
